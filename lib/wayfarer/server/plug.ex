defmodule Wayfarer.Server.Plug do
  @moduledoc """
  Plug pipeline to handle inbound HTTP connections.
  """

  alias Wayfarer.{Router, Server.Proxy, Target.Selector}
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
  def call(conn, config) when is_atom(config.module) do
    conn = put_private(conn, :wayfarer, %{listener: config})

    listener = {config.scheme, config.address, config.port}

    with {:ok, targets} <- Router.find_healthy_targets(config.module, listener, conn.host),
         {:ok, targets, algorithm} <- split_targets_and_algorithms(targets),
         {:ok, target} <- Selector.choose(conn, targets, algorithm) do
      do_proxy(conn, target)
    else
      :error -> bad_gateway(conn)
      {:error, reason} -> internal_error(conn, reason)
    end
  end

  def call(conn, _config), do: bad_gateway(conn)

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
end
