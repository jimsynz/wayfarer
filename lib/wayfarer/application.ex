defmodule Wayfarer.Application do
  @moduledoc false

  use Application

  @impl true
  @spec start(any, any) :: {:error, any} | {:ok, pid}
  def start(_type, _args) do
    []
    |> maybe_append_child(:start_target_supervisor?, Wayfarer.Target.Supervisor)
    |> maybe_append_child(:start_listener_supervisor?, Wayfarer.Listener.Supervisor)
    |> Supervisor.start_link(strategy: :one_for_one, name: Wayfarer.Supervisor)
  end

  defp maybe_append_child(children, config_key, child, default \\ true) do
    if Application.get_env(:wayfarer, config_key, default) do
      Enum.concat(children, [child])
    else
      children
    end
  end
end
