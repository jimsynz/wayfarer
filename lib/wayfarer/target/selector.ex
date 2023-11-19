defmodule Wayfarer.Target.Selector do
  @moduledoc """
  Given a list of targets and an algorithm decide which target the request
  should be forwarded to.
  """

  alias Plug.Conn
  alias Wayfarer.{Router, Target.ActiveConnections, Target.TotalConnections}

  import Plug.Conn

  @typedoc """
  The algorithm used to select which target to forward requests to (when there
  is more than one matching target).
  """
  @type algorithm :: :least_connections | :random | :round_robin | :sticky

  @doc """
  A guard for testing if an algorithm is supported.
  """
  @spec is_algorithm(any) :: Macro.output()
  defguard is_algorithm(algorithm)
           when algorithm in ~w[least_connections random round_robin sticky]a

  @doc """
  Tries to choose a target from the list of targets to send the request to based
  on the chosen algorithm.
  """
  @spec choose(Conn.t(), [Router.target()], Router.algorithm()) :: {:ok, Router.target()} | :error

  # We can't choose from an empty list.
  def choose(_conn, [], _), do: :error

  # When there's only one target, we don't need to choose anything.
  def choose(_conn, [target], _), do: {:ok, target}

  # Sticky targets try and use the same target for each request from the same
  # client if possible.
  def choose(conn, targets, :sticky) do
    peer = get_peer_data(conn)
    listener = conn.private.wayfarer.listener

    index =
      :erlang.phash2(
        {listener.address, listener.port, conn.remote_ip, peer.address, peer.port},
        length(targets)
      )

    targets
    |> Enum.at(index, :error)
    |> case do
      :error -> :error
      target -> {:ok, target}
    end
  end

  def choose(_conn, targets, :random) do
    {:ok, Enum.random(targets)}
  end

  # Choose the target with the fewest active connections from the list.
  def choose(_conn, targets, :least_connections) do
    targets
    |> ActiveConnections.request_count()
    |> case do
      request_counts when map_size(request_counts) == 0 ->
        {:ok, Enum.random(targets)}

      request_counts ->
        {:ok,
         request_counts
         |> Enum.min_by(&elem(&1, 1))
         |> elem(0)}
    end
  end

  # Select from targets sequentially.
  def choose(_conn, targets, :round_robin) do
    {target, _} =
      targets
      |> TotalConnections.proxy_count()
      |> Enum.min_by(&elem(&1, 1), &<=/2, fn -> {Enum.random(targets), 0} end)

    {:ok, target}
  end
end
