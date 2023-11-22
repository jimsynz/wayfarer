defmodule Wayfarer.Server.Proxy do
  @moduledoc """
  Uses Mint to convert a Plug connection into an outgoing HTTP request to a
  specific target.
  """

  alias Mint.HTTP
  alias Plug.Conn

  alias Wayfarer.{
    Router,
    Target.ActiveConnections,
    Target.ConnectionRecycler,
    Target.TotalConnections
  }

  require Logger

  @connect_timeout 5_000
  @idle_timeout 5_000

  @doc """
  Convert the request conn into an HTTP request to the specified target.
  """
  @spec request(Conn.t(), Router.target()) :: Conn.t()
  def request(conn, {scheme, address, port} = target) do
    with {:ok, mint} <- connect(scheme, address, port, conn.host),
         :ok <- ActiveConnections.connect(target),
         :ok <- TotalConnections.proxy_connect(target),
         {:ok, body, conn} <- read_request_body(conn),
         {:ok, mint, req} <- send_request(conn, mint, body),
         {:ok, conn, mint} <- proxy_responses(conn, mint, req),
         :ok <- ConnectionRecycler.checkin(scheme, address, port, conn.host, mint) do
      conn
    else
      error -> handle_error(error, conn, target)
    end
  end

  defp connect(scheme, address, port, hostname) do
    with {:ok, mint} <- ConnectionRecycler.try_checkout(scheme, address, port, hostname) do
      {:ok, mint}
    else
      :error -> HTTP.connect(scheme, address, port, hostname: hostname, timeout: @connect_timeout)
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_error({:error, _, reason}, conn, target),
    do: handle_error({:error, reason}, conn, target)

  defp handle_error({:error, reason}, conn, {scheme, address, port}) do
    Logger.error(
      "Proxy error [phase=#{connection_phase(conn)},ip=#{:inet.ntoa(address)},port=#{port},proto=#{scheme}]: #{message(reason)}"
    )

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
          :unknown -> proxy_responses(conn, mint, req)
          {:ok, mint, responses} -> handle_responses(responses, conn, mint, req)
          {:error, _, reason, _} -> {:error, reason}
        end
    after
      @idle_timeout -> {:error, conn, :idle_timeout}
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

  # This is bad - we need to figure out how to stream the body, but it's fine
  # for now.
  defp read_request_body(conn, body \\ <<>>) do
    case Conn.read_body(conn) do
      {:ok, chunk, conn} -> {:ok, body <> chunk, conn}
      {:more, chunk, conn} -> read_request_body(conn, body <> chunk)
      {:error, reason} -> {:error, conn, reason}
    end
  end

  defp send_request(conn, mint, body) do
    HTTP.request(
      mint,
      conn.method,
      conn.request_path,
      proxy_headers(conn),
      body
    )
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

    headers = conn.req_headers |> Enum.reject(&(elem(&1, 0) == "connection"))

    [
      {"forwarded", "by=#{listener};for=#{client};host=#{conn.host};proto=#{conn.scheme}"},
      {"connection", "keep-alive"}
      | headers
    ]
  end
end
