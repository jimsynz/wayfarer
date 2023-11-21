defmodule Wayfarer.Target.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_) do
    [
      {Registry, keys: :unique, name: Wayfarer.Target.Registry},
      {DynamicSupervisor, name: Wayfarer.Target.DynamicSupervisor, strategy: :one_for_one},
      Wayfarer.Target.ActiveConnections,
      Wayfarer.Target.TotalConnections,
      Wayfarer.Target.ConnectionRecycler
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end
end
