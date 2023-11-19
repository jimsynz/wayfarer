defmodule Wayfarer.Application do
  @moduledoc false

  use Application

  @impl true
  @spec start(any, any) :: {:error, any} | {:ok, pid}
  def start(_type, _args) do
    []
    |> maybe_add_child(Wayfarer.Target.Supervisor, :start_target_supervisor?)
    |> maybe_add_child(Wayfarer.Listener.Supervisor, :start_listener_supervisor?)
    |> maybe_add_child(Wayfarer.Server.Supervisor, :start_server_supervisor?)
    |> Supervisor.start_link(strategy: :one_for_one, name: Wayfarer.Supervisor)
  end

  defp maybe_add_child(children, child_spec, option) do
    :wayfarer
    |> Application.get_env(option, true)
    |> if do
      Enum.concat(children, [child_spec])
    else
      children
    end
  end
end
