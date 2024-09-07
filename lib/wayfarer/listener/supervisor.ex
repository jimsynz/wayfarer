defmodule Wayfarer.Listener.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_) do
    [
      {DynamicSupervisor, name: Wayfarer.Listener.DynamicSupervisor, strategy: :one_for_one},
      {Registry, name: Wayfarer.Listener.Registry, keys: :unique}
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end
end
