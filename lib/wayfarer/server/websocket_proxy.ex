defmodule Wayfarer.Server.WebSocketProxy do
  @moduledoc """
  When a connection is upgraded to a websocket, we switch from handing via
  `Plug` to `WebSock` via `WebSockAdapter`.

  The outgoing connection is made using `Mint.WebSocket`.
  """

  @behaviour WebSock

  alias Mint.WebSocket
  alias Plug.Conn
  alias Wayfarer.Telemetry
  require Logger

  @default_opts [extensions: [WebSocket.PerMessageDeflate]]

  @doc false
  @impl true
  def init({mint, conn, proto}) when proto in [:ws, :wss] do
    request_path =
      case {conn.request_path, conn.query_string} do
        {path, nil} -> path
        {path, ""} -> path
        {path, query} -> path <> "?" <> query
      end

    case WebSocket.upgrade(proto, mint, request_path, proxy_headers(conn), @default_opts) do
      {:ok, mint, ref} -> {:ok, %{mint: mint, ref: ref, status: :init, buffer: [], conn: conn}}
      {:error, _mint, reason} -> {:error, reason}
    end
  end

  def init({mint, conn, :https}), do: init({mint, conn, :wss})
  def init({mint, conn, :http}), do: init({mint, conn, :ws})

  @doc false
  @impl true
  def handle_control({frame, [{:opcode, :ping}]}, state) do
    with {:ok, websocket, data} <- WebSocket.encode(state.websocket, {:ping, frame}),
         {:ok, mint} <- WebSocket.stream_request_body(state.mint, state.ref, data) do
      conn = request_client_frame(state.conn, {:ping, frame})

      {:ok, %{state | websocket: websocket, mint: mint, conn: conn}}
    else
      error -> handle_error(error, state)
    end
  end

  def handle_control({frame, [{:opcode, frame_type}]}, state) do
    conn = request_client_frame(state.conn, {frame_type, frame})

    {:ok, %{state | conn: conn}}
  end

  @doc false
  @impl true
  def handle_in({payload, [{:opcode, frame_type}]}, state) when state.status == :init do
    frame = {frame_type, payload}
    buffer = [frame | state.buffer]
    conn = request_client_frame(state.conn, frame)

    {:ok, %{state | buffer: buffer, conn: conn}}
  end

  def handle_in({payload, [{:opcode, frame_type}]}, state) do
    with {:ok, websocket, data} <- WebSocket.encode(state.websocket, {frame_type, payload}),
         {:ok, mint} <- WebSocket.stream_request_body(state.mint, state.ref, data) do
      conn = request_client_frame(state.conn, {frame_type, payload})

      {:ok, %{state | websocket: websocket, mint: mint, conn: conn}}
    else
      error -> handle_error(error, state)
    end
  end

  @doc false
  @impl true
  def handle_info(msg, state) when state.status == :init do
    with {:ok, mint, result} <- WebSocket.stream(state.mint, msg),
         {:ok, result} <- handle_upgrade_response(result, state.ref),
         {:ok, mint, websocket} <- WebSocket.new(mint, state.ref, result.status, result.headers),
         state <- Map.merge(state, %{status: :connected, websocket: websocket, mint: mint}),
         {:ok, state} <- empty_buffer(state),
         {:ok, messages, state} <- decode_frames(result.data, state) do
      response_for_messages(messages, state)
    else
      error -> handle_error(error, state)
    end
  end

  def handle_info(msg, state) when state.status == :connected do
    with {:ok, mint, result} <- WebSocket.stream(state.mint, msg),
         {:ok, frames} <- handle_websocket_data(result, state.ref),
         {:ok, messages, state} <- decode_frames(frames, %{state | mint: mint}) do
      response_for_messages(messages, state)
    else
      error -> handle_error(error, state)
    end
  end

  @doc false
  @impl true
  def terminate(_reason, _state), do: :ok

  defp handle_error({:error, _, %{reason: reason}, _}, state),
    do: handle_error({:error, reason}, state)

  defp handle_error({:error, reason, state}, _state), do: handle_error({:error, reason}, state)

  defp handle_error({:error, reason}, state) do
    Logger.debug(fn ->
      "Dropping WebSocket connection for reason: #{inspect(reason)}"
    end)

    {:stop, :normal, state}
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

    req_headers =
      conn.req_headers
      |> Enum.reject(
        &(elem(&1, 0) in [
            "connection",
            "upgrade",
            "sec-websocket-extensions",
            "sec-websocket-key",
            "sec-websocket-version"
          ])
      )

    [
      {"forwarded", "by=#{listener};for=#{client};host=#{conn.host};proto=#{conn.scheme}"}
      | req_headers
    ]
  end

  defp empty_buffer(state) when state.buffer == [], do: {:ok, state}
  defp empty_buffer(state), do: do_empty_buffer(Enum.reverse(state.buffer), %{state | buffer: []})
  defp do_empty_buffer([], state), do: {:ok, state}

  defp do_empty_buffer([head | tail], state) do
    with {:ok, websocket, data} <- WebSocket.encode(state.websocket, head),
         {:ok, mint} <- WebSocket.stream_request_body(state.mint, state.ref, data) do
      conn = request_client_frame(state.conn, head)

      do_empty_buffer(tail, %{state | websocket: websocket, mint: mint, conn: conn})
    end
  end

  defp handle_upgrade_response(result, ref), do: handle_upgrade_response(result, ref, %{data: []})
  defp handle_upgrade_response([{:done, ref}], ref, result), do: {:ok, result}

  defp handle_upgrade_response([{:status, ref, status} | tail], ref, result) do
    handle_upgrade_response(tail, ref, Map.put(result, :status, status))
  end

  defp handle_upgrade_response([{:headers, ref, headers} | tail], ref, result) do
    handle_upgrade_response(tail, ref, Map.put(result, :headers, headers))
  end

  defp handle_upgrade_response([{:data, ref, data} | tail], ref, result) do
    result = Map.update!(result, :data, &[data | &1])
    handle_upgrade_response(tail, ref, result)
  end

  defp handle_websocket_data(data, ref),
    do: handle_websocket_data(data, ref, [])

  defp handle_websocket_data([], _ref, messages), do: {:ok, Enum.reverse(messages)}

  defp handle_websocket_data([{:data, ref, data} | tail], ref, messages),
    do: handle_websocket_data(tail, ref, [data | messages])

  defp decode_frames(frames, state) do
    frames
    |> Enum.reduce_while({:ok, [], state}, fn frame, {:ok, messages, state} ->
      case decode_frame(state, frame) do
        {:ok, new_messages, state} -> {:cont, {:ok, [new_messages, messages], state}}
        {:error, reason, state} -> {:halt, {:error, reason, state}}
      end
    end)
    |> case do
      {:ok, messages, state} -> {:ok, List.flatten(messages), state}
      {:error, reason, state} -> {:error, reason, state}
    end
  end

  defp decode_frame(state, frame) do
    case WebSocket.decode(state.websocket, frame) do
      {:ok, websocket, frames} when is_list(frames) ->
        conn = Enum.reduce(frames, state.conn, &request_server_frame(&2, &1))
        {:ok, frames, %{state | websocket: websocket, conn: conn}}

      {:error, websocket, reason} ->
        {:error, reason, %{state | websocket: websocket}}
    end
  end

  defp response_for_messages([], state), do: {:ok, state}

  defp response_for_messages(messages, state) do
    case Enum.split_with(messages, &(elem(&1, 0) == :close)) do
      {[], messages} -> {:push, messages, state}
      {[{:close, code, _} | _], messages} -> {:stop, :normal, code, messages, state}
    end
  end

  defp request_client_frame(conn, {frame_type, frame}) do
    frame_size = byte_size(frame)

    conn
    |> Telemetry.increment_metrics(%{
      client_frame_bytes: frame_size,
      client_frame_count: 1
    })
    |> Telemetry.request_client_frame(frame_size, frame_type)
  end

  defp request_server_frame(conn, {frame_type, frame}) do
    frame_size = byte_size(frame)

    conn
    |> Telemetry.increment_metrics(%{
      server_frame_bytes: frame_size,
      server_frame_count: 1
    })
    |> Telemetry.request_server_frame(frame_size, frame_type)
  end
end
