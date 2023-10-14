defmodule Wayfarer.Target.Supervisor do
  @moduledoc """
  Supervisor for HTTP Targets.
  """

  use Supervisor

  @doc false
  @spec start_link(any) :: Supervisor.on_start()
  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg)

  @doc false
  @impl true
  def init(_arg) do
    [
      {Registry, keys: :unique, name: Wayfarer.Target.Registry},
      {DynamicSupervisor, name: Wayfarer.Target.DynamicSupervisor},
      Wayfarer.Target.Table
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end
end
