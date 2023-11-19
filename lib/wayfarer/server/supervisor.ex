defmodule Wayfarer.Server.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_) do
    [
      {Registry, keys: :unique, name: Wayfarer.Server.Registry}
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end
end
