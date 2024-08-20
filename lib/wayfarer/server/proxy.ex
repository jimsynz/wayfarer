defmodule Wayfarer.Server.Proxy do
  @moduledoc """
  Uses Mint to convert a Plug connection into an outgoing HTTP request to a
  specific target.
  """

  alias Mint.{HTTP, HTTP1, HTTP2}
  alias Plug.Conn
  alias Wayfarer.{Router, Target.ActiveConnections, Target.TotalConnections, Telemetry}
  require Logger

  @connect_timeout 5_000
  @idle_timeout 5_000

  @doc """
  Convert the request conn into an HTTP request to the specified target.
  """
  @spec request(Conn.t(), Router.target()) :: Conn.t()
  def request(conn, target) do
    with {:ok, mint} <- connect(conn, target),
         :ok <- ActiveConnections.connect(target),
         :ok <- TotalConnections.proxy_connect(target) do
      handle_request(mint, conn, target)
    else
      error ->
        conn
        |> Telemetry.request_exception(:error, error)
        |> handle_error(error, target)
    end
  end

  defp handle_request(mint, conn, {proto, _, _, _}) do
    if http1?(conn) && connection_wants_upgrade?(conn) && upgrade_is_websocket?(conn) do
      handle_websocket_request(mint, conn, proto)
    else
      handle_http_request(mint, conn)
    end
  end

  defp handle_http_request(mint, conn) do
    with {:ok, mint, req} <- send_request(conn, mint),
         {:ok, mint, conn} <- stream_request_body(conn, mint, req),
         {:ok, conn, _mint} <- proxy_responses(conn, mint, req) do
      conn
      |> Telemetry.request_stop()
    end
  end

  defp handle_websocket_request(mint, conn, proto) do
    conn
    |> WebSockAdapter.upgrade(Wayfarer.Server.WebSocketProxy, {mint, conn, proto}, compress: true)
    |> Telemetry.request_upgraded()
  end

  defp connect(conn, {:ws, address, port, transport}),
    do: connect(conn, {:http, address, port, transport})

  defp connect(conn, {:wss, address, port, transport}),
    do: connect(conn, {:https, address, port, transport})

  defp connect(conn, {scheme, address, port, :http1}) when is_tuple(address),
    do: HTTP1.connect(scheme, address, port, hostname: conn.host, timeout: @connect_timeout)

  defp connect(conn, {scheme, address, port, :http2}) when is_tuple(address),
    do: HTTP2.connect(scheme, address, port, hostname: conn.host, timeout: @connect_timeout)

  defp connect(conn, {scheme, address, port, :auto}) when is_tuple(address),
    do: HTTP.connect(scheme, address, port, hostname: conn.host, timeout: @connect_timeout)

  defp handle_error(conn, {:error, _, reason}, target),
    do: handle_error(conn, {:error, reason}, target)

  defp handle_error(conn, {:error, reason}, {scheme, address, port, transport}) do
    Logger.error(fn ->
      phase = connection_phase(conn)
      ip = :inet.ntoa(address)

      "Proxy error [phase=#{phase},ip=#{ip},port=#{port},proto=#{scheme},trans=#{transport}]: #{message(reason)}"
    end)

    if conn.halted || conn.state in [:sent, :chunked, :upgraded] do
      # Sadly there's not much more we can do here.
      Conn.halt(conn)
    else
      {status, body} = status_and_response(reason)

      conn
      |> Conn.put_resp_content_type("text/plain")
      |> Conn.send_resp(status, body)
    end
  end

  defp http1?(%{private: %{wayfarer: %{transport: :http1}}}), do: true
  defp http1?(_), do: false

  defp connection_wants_upgrade?(conn) do
    case Conn.get_req_header(conn, "connection") do
      ["Upgrade"] ->
        true

      ["upgrade"] ->
        true

      [] ->
        false

      maybe ->
        maybe
        |> Enum.flat_map(&String.split(&1, ~r/,\s*/))
        |> Enum.map(fn chunk ->
          chunk
          |> String.trim()
          |> String.downcase()
        end)
        |> Enum.member?("upgrade")
    end
  end

  defp upgrade_is_websocket?(conn) do
    case Conn.get_req_header(conn, "upgrade") do
      ["websocket"] ->
        true

      [] ->
        false

      maybe ->
        maybe
        |> Enum.flat_map(&String.split(&1, ~r/,\s*/))
        |> Enum.map(fn chunk ->
          chunk
          |> String.trim()
          |> String.split("/")
          |> hd()
          |> String.downcase()
        end)
        |> Enum.member?("websocket")
    end
  end

  defp connection_phase(conn) when conn.state in [:chunked, :upgraded], do: "stream"
  defp connection_phase(conn) when conn.halted, do: "done"
  defp connection_phase(conn) when conn.state == :sent, do: "done"
  defp connection_phase(_conn), do: "init"

  defp message(error) when is_exception(error), do: Exception.message(error)
  defp message(error) when is_binary(error), do: error
  defp message(error), do: inspect(error)

  defp status_and_response(:idle_timeout), do: {504, "Gateway Timeout"}
  defp status_and_response(error) when error.reason == :timeout, do: {504, "Gateway Timeout"}

  defp status_and_response(error) when is_struct(error, Mint.TransportError),
    do: {502, "Bad Gateway"}

  defp status_and_response(_error), do: {500, "Internal Error"}

  defp proxy_responses(conn, mint, req) do
    receive do
      message ->
        case HTTP.stream(mint, message) do
          :unknown ->
            proxy_responses(conn, mint, req)

          {:ok, mint, responses} ->
            handle_responses(conn, responses, mint, req)

          {:error, _, reason, _} ->
            {:error, reason}
        end
    after
      @idle_timeout -> {:error, :idle_timeout}
    end
  end

  defp handle_responses(conn, [], mint, req), do: proxy_responses(conn, mint, req)

  defp handle_responses(conn, [{:status, req, status} | responses], mint, req) do
    conn
    |> Conn.put_status(status)
    |> Telemetry.request_received_status(status)
    |> handle_responses(responses, mint, req)
  end

  defp handle_responses(conn, [{:headers, req, headers} | responses], mint, req) do
    headers
    |> Enum.reduce(conn, fn {header_name, header_value}, conn ->
      conn
      |> Conn.put_resp_header(header_name, header_value)
    end)
    |> handle_responses(responses, mint, req)
  end

  defp handle_responses(conn, [{:data, req, body} | responses], mint, req)
       when conn.state == :chunked do
    case Conn.chunk(conn, body) do
      {:ok, conn} ->
        body_size = byte_size(body)

        conn
        |> Telemetry.increment_metrics(%{resp_body_bytes: body_size})
        |> Telemetry.request_resp_body_chunk(body_size)
        |> handle_responses(responses, mint, req)

      {:error, reason} ->
        {:error, conn, reason}
    end
  end

  defp handle_responses(conn, [{:data, req, body} | responses], mint, req) do
    # We need to check here for a content-length or transfer encoding header and
    # deal with it.  This should be refactored out into a proxy state rather
    # than using the conn as our state.

    body_size = byte_size(body)

    case Conn.get_resp_header(conn, "content-length") do
      [] ->
        conn
        |> Conn.send_chunked(conn.status)
        |> Telemetry.request_resp_started()
        |> handle_responses([{:data, req, body} | responses], mint, req)

      [length] ->
        if String.to_integer(length) == body_size do
          conn =
            conn
            |> Conn.send_resp(conn.status, body)
            |> Telemetry.request_resp_started()
            |> Telemetry.increment_metrics(%{resp_body_bytes: body_size})
            |> Telemetry.request_resp_body_chunk(body_size)
            |> Conn.halt()

          {:ok, conn, mint}
        else
          conn =
            conn
            |> Telemetry.increment_metrics(%{resp_body_bytes: body_size})
            |> Telemetry.request_resp_body_chunk(body_size)
            |> Conn.send_chunked(conn.status)

          handle_responses(conn, [{:data, req, body} | responses], mint, req)
        end
    end
  end

  defp handle_responses(conn, [{:done, req} | _], mint, req) do
    {:ok, Conn.halt(conn), mint}
  end

  defp handle_responses(conn, [{:error, req, reason} | _], _mint, req), do: {:error, conn, reason}

  defp send_request(conn, mint) do
    request_path =
      case {conn.request_path, conn.query_string} do
        {path, nil} -> path
        {path, ""} -> path
        {path, query} -> path <> "?" <> query
      end

    HTTP.request(
      mint,
      conn.method,
      request_path,
      proxy_headers(conn),
      :stream
    )
  end

  defp stream_request_body(conn, mint, req) do
    case Conn.read_body(conn) do
      {:ok, <<>>, conn} ->
        with {:ok, mint} <- HTTP.stream_request_body(mint, req, :eof) do
          conn =
            conn
            |> Telemetry.set_metrics(%{req_body_bytes: 0, req_body_chunks: 0})

          {:ok, mint, conn}
        end

      {:ok, chunk, conn} ->
        with {:ok, mint} <- HTTP.stream_request_body(mint, req, chunk),
             {:ok, mint} <- HTTP.stream_request_body(mint, req, :eof) do
          chunk_size = byte_size(chunk)

          conn =
            conn
            |> Telemetry.increment_metrics(%{req_body_bytes: chunk_size, req_body_chunks: 1})
            |> Telemetry.request_req_body_chunk(chunk_size)

          {:ok, mint, conn}
        end

      {:more, chunk, conn} ->
        with {:ok, mint} <- HTTP.stream_request_body(mint, req, chunk) do
          chunk_size = byte_size(chunk)

          conn
          |> Telemetry.increment_metrics(%{req_body_bytes: chunk_size, req_body_chunks: 1})
          |> Telemetry.request_req_body_chunk(chunk_size)
          |> stream_request_body(mint, req)
        end

      {:error, reason} ->
        {:error, conn, reason}
    end
  end

  defp proxy_headers(conn) do
    listener =
      conn.private.wayfarer.listener
      |> case do
        %{address: address, port: port} when tuple_size(address) == 8 ->
          "[#{:inet.ntoa(address)}]:#{port}"

        %{address: address, port: port} ->
          "#{:inet.ntoa(address)}:#{port}"
      end

    client =
      conn
      |> Conn.get_peer_data()
      |> case do
        %{address: address, port: port} when tuple_size(address) == 8 ->
          "[#{:inet.ntoa(address)}]:#{port}"

        %{address: address, port: port} ->
          "#{:inet.ntoa(address)}:#{port}"
      end

    [
      {"forwarded", "by=#{listener};for=#{client};host=#{conn.host};proto=#{conn.scheme}"}
      | conn.req_headers
    ]
  end
end
