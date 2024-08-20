defmodule Wayfarer.Server.Plug do
  @moduledoc """
  Plug pipeline to handle inbound HTTP connections.
  """

  alias Wayfarer.{Router, Server.Proxy, Target.Selector, Telemetry}
  require Logger

  import Plug.Conn
  @behaviour Plug

  @doc false
  @impl true
  @spec init(Enumerable.t()) :: map
  def init(config), do: Map.new(config)

  @doc false
  @impl true
  @spec call(Plug.Conn.t(), map) :: Plug.Conn.t()
  def call(conn, config) do
    transport = get_transport(conn)

    conn
    |> put_private(:wayfarer, %{listener: config, transport: transport})
    |> Telemetry.request_start()
    |> do_call(config)
  end

  defp do_call(conn, config) when is_atom(config.module) do
    listener = {config.scheme, config.address, config.port}

    with {:ok, targets} <- Router.find_healthy_targets(config.module, listener, conn.host),
         {:ok, targets, algorithm} <- split_targets_and_algorithms(targets),
         {:ok, target} <- Selector.choose(conn, targets, algorithm) do
      conn
      |> Telemetry.request_routed(target, algorithm)
      |> do_proxy(target)
    else
      :error ->
        conn
        |> Telemetry.request_exception(:error, :target_not_found)
        |> bad_gateway()

      {:error, reason} ->
        conn
        |> Telemetry.request_exception(:error, reason)
        |> internal_error(reason)
    end
  rescue
    exception ->
      conn
      |> Telemetry.request_exception(:exception, exception, __STACKTRACE__)
      |> internal_error(exception)
  catch
    reason ->
      conn
      |> Telemetry.request_exception(:throw, reason)
      |> internal_error(reason)

    kind, reason ->
      conn
      |> Telemetry.request_exception(kind, reason)
      |> internal_error(reason)
  end

  defp do_call(conn, _config) do
    conn
    |> Telemetry.request_exception(:error, :unrecognised_request)
    |> bad_gateway()
  end

  defp internal_error(conn, reason) do
    Logger.error("Internal error when routing proxy request: #{inspect(reason)}")

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(500, "Internal Error")
  end

  defp bad_gateway(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(502, "Bad Gateway")
  end

  defp do_proxy(conn, {:plug, {module, opts}}), do: module.call(conn, module.init(opts))
  defp do_proxy(conn, {:plug, module}), do: module.call(conn, module.init([]))
  defp do_proxy(conn, target), do: Proxy.request(conn, target)

  # This is lazy, but we assume that the algorithm is consistent across all
  # matching targets.
  defp split_targets_and_algorithms([]), do: :error
  defp split_targets_and_algorithms([{target, algorithm}]), do: {:ok, [target], algorithm}

  defp split_targets_and_algorithms([{target, algorithm} | tail]),
    do: split_targets_and_algorithms(tail, [target], algorithm)

  defp split_targets_and_algorithms([{target, algorithm} | tail], targets, algorithm),
    do: split_targets_and_algorithms(tail, [target | targets], algorithm)

  defp split_targets_and_algorithms([], targets, algorithm), do: {:ok, targets, algorithm}

  defp get_transport(%{adapter: {Bandit.Adapter, %{transport: %Bandit.HTTP1.Socket{}}}}),
    do: :http1

  defp get_transport(%{adapter: {Bandit.Adapter, %{transport: %Bandit.HTTP2.Stream{}}}}),
    do: :http2

  defp get_transport(_), do: :unknown
end
