defmodule Wayfarer.Target.Check do
  @moduledoc """
  A GenServer which represents a single check to an HTTP endpoint.
  """

  use GenServer, restart: :transient
  alias Mint.{HTTP, HTTP1, HTTP2, WebSocket}
  alias Wayfarer.{Target, Target.TotalConnections, Telemetry}
  require Logger

  @type state :: %{
          conn: struct(),
          req: reference(),
          scheme: :http | :https | :ws | :wss,
          address: :inet.ip_address(),
          port: :socket.port_number(),
          uri: URI.t(),
          ref: any,
          method: String.t(),
          headers: [{String.t(), String.t()}],
          hostname: String.t(),
          transport: :http1 | :http2 | :auto,
          span: map
        }

  @doc false
  @impl true
  def init(state), do: {:ok, state, {:continue, :start_check}}

  @doc false
  @impl true
  @spec handle_continue(:start_check, state) :: {:noreply, state, timeout} | {:stop, :normal, nil}
  def handle_continue(:start_check, state) do
    state =
      state
      |> Map.put(:span, %{
        metadata: %{
          target: %{scheme: state.scheme, address: state.address, port: state.port},
          method: state.method,
          uri: state.uri,
          hostname: state.hostname,
          telemetry_span_context: make_ref()
        }
      })
      |> Telemetry.health_check_start()

    with {:ok, state} <- connect(state),
         {:ok, state} <- request(state) do
      {:noreply, state, state.response_timeout}
    else
      {:error, reason} ->
        check_failed(state, reason)

      {:error, _conn, reason} ->
        check_failed(state, reason)
    end
  end

  @doc false
  @impl true
  def handle_info(:timeout, state), do: check_failed(state, :timeout)

  def handle_info(message, state) do
    with {:ok, conn, responses} <- WebSocket.stream(state.conn, message),
         :ok <-
           TotalConnections.health_check_connect(
             {state.scheme, state.address, state.port, state.transport}
           ),
         {:ok, status} <- get_status_response(conn, responses) do
      if Enum.any?(state.success_codes, &Enum.member?(&1, status)) do
        Target.check_passed(state.ref)
        Telemetry.health_check_pass(state, status)
        {:stop, :normal, nil}
      else
        check_failed(state, "received #{status} status code")
      end
    else
      {:continue, conn} ->
        {:noreply, Map.put(state, :conn, conn)}

      :unknown ->
        check_failed(state, "Received unknown message: `#{inspect(message)}`")

      {:error, _conn, error, _responses} ->
        check_failed(state, error)
    end
  end

  defp connect(state) when state.scheme == :ws,
    do: connect(%{state | scheme: :http})

  defp connect(state) when state.scheme == :wss,
    do: connect(%{state | scheme: :https})

  defp connect(state) when state.transport == :http1 do
    with {:ok, conn} <-
           HTTP1.connect(state.scheme, state.address, state.port,
             timeout: state.connect_timeout,
             hostname: state.hostname
           ) do
      {:ok, Telemetry.health_check_connect(Map.put(state, :conn, conn), :http1)}
    end
  end

  defp connect(state) when state.transport == :http2 do
    with {:ok, conn} <-
           HTTP2.connect(state.scheme, state.address, state.port,
             timeout: state.connect_timeout,
             hostname: state.hostname
           ) do
      {:ok, Telemetry.health_check_connect(Map.put(state, :conn, conn), :http2)}
    end
  end

  defp connect(state) do
    with {:ok, conn} <-
           HTTP.connect(state.scheme, state.address, state.port,
             timeout: state.connect_timeout,
             hostname: state.hostname
           ) do
      transport =
        case conn do
          %Mint.HTTP1{} -> :http1
          %Mint.HTTP2{} -> :http2
        end

      {:ok, Telemetry.health_check_connect(Map.put(state, :conn, conn), transport)}
    end
  end

  defp request(state) when state.scheme in [:ws, :wss] do
    with {:ok, conn, req} <-
           WebSocket.upgrade(state.scheme, state.conn, state.path, state.headers, []) do
      state = Map.merge(state, %{conn: conn, req: req})

      {:ok, Telemetry.health_check_request(state)}
    end
  end

  defp request(state) do
    with {:ok, conn, req} <-
           HTTP.request(state.conn, state.method, state.path, state.headers, nil) do
      state = Map.merge(state, %{conn: conn, req: req})

      {:ok, Telemetry.health_check_request(state)}
    end
  end

  defp check_failed(state, reason) when is_binary(reason) do
    Target.check_failed(state.ref)
    Telemetry.health_check_fail(state, reason)

    Logger.warning(fn -> "Health check failed for #{state.method} #{state.uri}: #{reason}." end)
    {:stop, :normal, nil}
  end

  defp check_failed(state, exception) when is_exception(exception) do
    Target.check_failed(state.ref)
    Telemetry.health_check_fail(state, exception)

    Logger.warning(fn ->
      "Health check failed for #{state.method} #{state.uri}: #{Exception.message(exception)}"
    end)

    {:stop, :normal, nil}
  end

  defp check_failed(state, reason) do
    Target.check_failed(state.ref)
    Telemetry.health_check_fail(state, reason)

    Logger.warning(fn ->
      "Health check failed for #{state.method} #{state.uri}: `#{inspect(reason)}`"
    end)

    {:stop, :normal, nil}
  end

  defp get_status_response(conn, []), do: {:continue, conn}
  defp get_status_response(_conn, [{:status, _, status} | _]), do: {:ok, status}
  defp get_status_response(conn, [_ | tail]), do: get_status_response(conn, tail)
end
