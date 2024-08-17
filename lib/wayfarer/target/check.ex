defmodule Wayfarer.Target.Check do
  @moduledoc """
  A GenServer which represents a single check to an HTTP endpoint.
  """

  use GenServer, restart: :transient
  alias Mint.{HTTP, HTTP1, HTTP2, WebSocket}
  alias Wayfarer.{Target, Target.TotalConnections}
  require Logger

  @doc false
  @impl true
  def init(state), do: {:ok, state, {:continue, :start_check}}

  @doc false
  @impl true
  def handle_continue(:start_check, state) do
    with {:ok, conn} <- connect(state),
         {:ok, conn, req} <- request(Map.put(state, :conn, conn)) do
      state =
        state
        |> Map.merge(%{conn: conn, req: req})

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
  def handle_info(:timeout, state), do: check_failed(state, "request timeout expired.")

  def handle_info(message, state) do
    with {:ok, conn, responses} <- WebSocket.stream(state.conn, message),
         :ok <-
           TotalConnections.health_check_connect(
             {state.scheme, state.address, state.port, state.transport}
           ),
         {:ok, status} <- get_status_response(conn, responses) do
      if Enum.any?(state.success_codes, &Enum.member?(&1, status)) do
        Target.check_passed(state.ref)
        {:stop, :normal, nil}
      else
        check_failed(state, "received #{status} status code")
      end
    else
      {:continue, conn} ->
        {:noreply, %{state | conn: conn}}

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
    HTTP1.connect(state.scheme, state.address, state.port,
      timeout: state.connect_timeout,
      hostname: state.hostname
    )
  end

  defp connect(state) when state.transport == :http2 do
    HTTP2.connect(state.scheme, state.address, state.port,
      timeout: state.connect_timeout,
      hostname: state.hostname
    )
  end

  defp connect(state) do
    HTTP.connect(state.scheme, state.address, state.port,
      timeout: state.connect_timeout,
      hostname: state.hostname
    )
  end

  defp request(state) when state.scheme in [:ws, :wss] do
    WebSocket.upgrade(state.scheme, state.conn, state.path, state.headers, [])
  end

  defp request(state) do
    HTTP.request(state.conn, state.method, state.path, state.headers, nil)
  end

  defp check_failed(state, reason) when is_binary(reason) do
    Target.check_failed(state.ref)
    Logger.warning("Health check failed for #{state.method} #{state.uri}: #{reason}.")
    {:stop, :normal, nil}
  end

  defp check_failed(state, exception) when is_exception(exception) do
    Target.check_failed(state.ref)

    Logger.warning(
      "Health check failed for #{state.method} #{state.uri}: #{Exception.message(exception)}"
    )

    {:stop, :normal, nil}
  end

  defp check_failed(state, reason) do
    Target.check_failed(state.ref)
    Logger.warning("Health check failed for #{state.method} #{state.uri}: `#{inspect(reason)}`")
    {:stop, :normal, nil}
  end

  defp get_status_response(conn, []), do: {:continue, conn}
  defp get_status_response(_conn, [{:status, _, status} | _]), do: {:ok, status}
  defp get_status_response(conn, [_ | tail]), do: get_status_response(conn, tail)
end
