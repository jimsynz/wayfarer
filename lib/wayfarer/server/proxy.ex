defmodule Wayfarer.Server.Proxy do
  @moduledoc """
  Uses Mint to convert a Plug connection into an outgoing HTTP request to a
  specific target.
  """

  alias Mint.{HTTP, HTTP1, HTTP2}
  alias Plug.Conn
  alias Wayfarer.{Router, Target.ActiveConnections, Target.TotalConnections}
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
      error -> handle_error(error, conn, target)
    end
  end

  defp handle_request(mint, conn, {proto, _, _, _}) do
    with ["Upgrade"] <- Conn.get_req_header(conn, "connection"),
         ["websocket"] <- Conn.get_req_header(conn, "upgrade") do
      handle_websocket_request(mint, conn, proto)
    else
      _ -> handle_http_request(mint, conn)
    end
  end

  defp handle_http_request(mint, conn) do
    with {:ok, mint, req} <- send_request(conn, mint),
         {:ok, mint, conn} <- stream_request_body(conn, mint, req),
         {:ok, conn, _mint} <- proxy_responses(conn, mint, req) do
      conn
    end
  end

  defp handle_websocket_request(mint, conn, proto) do
    WebSockAdapter.upgrade(conn, Wayfarer.Server.WebSocketProxy, {mint, conn, proto},
      compress: true
    )
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

  defp handle_error({:error, _, reason}, conn, target),
    do: handle_error({:error, reason}, conn, target)

  defp handle_error({:error, reason}, conn, {scheme, address, port, transport}) do
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

  defp connection_phase(nil), do: "connect"
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
            handle_responses(responses, conn, mint, req)

          {:error, _, reason, _} ->
            {:error, reason}
        end
    after
      @idle_timeout -> {:error, :idle_timeout}
    end
  end

  defp handle_responses([], conn, mint, req), do: proxy_responses(conn, mint, req)

  defp handle_responses([{:status, req, status} | responses], conn, mint, req),
    do: handle_responses(responses, Conn.put_status(conn, status), mint, req)

  defp handle_responses([{:headers, req, headers} | responses], conn, mint, req) do
    conn =
      headers
      |> Enum.reduce(conn, &Conn.put_resp_header(&2, elem(&1, 0), elem(&1, 1)))

    handle_responses(responses, conn, mint, req)
  end

  defp handle_responses([{:data, req, body} | responses], conn, mint, req)
       when conn.state == :chunked do
    case Conn.chunk(conn, body) do
      {:ok, conn} -> handle_responses(responses, conn, mint, req)
      {:error, reason} -> {:error, conn, reason}
    end
  end

  defp handle_responses([{:data, req, body} | responses], conn, mint, req) do
    # We need to check here for a content-length or transfer encoding header and
    # deal with it.  This should be refactored out into a proxy state rather
    # than using the conn as our state.

    case Conn.get_resp_header(conn, "content-length") do
      [] ->
        conn = Conn.send_chunked(conn, conn.status)
        handle_responses([{:data, req, body} | responses], conn, mint, req)

      [length] ->
        if String.to_integer(length) == byte_size(body) do
          conn =
            conn
            |> Conn.delete_resp_header("content-length")
            |> Conn.send_resp(conn.status, body)
            |> Conn.halt()

          {:ok, conn, mint}
        else
          conn =
            conn
            |> Conn.delete_resp_header("content-length")
            |> Conn.send_chunked(conn.status)

          handle_responses([{:data, req, body} | responses], conn, mint, req)
        end
    end
  end

  defp handle_responses([{:done, req} | _], conn, mint, req) do
    {:ok, Conn.halt(conn), mint}
  end

  defp handle_responses([{:error, req, reason} | _], conn, _mint, req), do: {:error, conn, reason}

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
      {:ok, chunk, conn} ->
        with {:ok, mint} <- HTTP.stream_request_body(mint, req, chunk),
             {:ok, mint} <- HTTP.stream_request_body(mint, req, :eof) do
          {:ok, mint, conn}
        end

      {:more, chunk, conn} ->
        with {:ok, mint} <- HTTP.stream_request_body(mint, req, chunk) do
          stream_request_body(conn, mint, req)
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
