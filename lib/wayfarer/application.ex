defmodule Wayfarer.Application do
  @moduledoc false

  use Application

  @impl true
  @spec start(any, any) :: {:error, any} | {:ok, pid}
  def start(_type, _args) do
    []
    |> start_listeners?()
    |> Supervisor.start_link(strategy: :one_for_one, name: Wayfarer.Supervisor)
  end

  defp start_listeners?(children) do
    if Application.get_env(:wayfarer, :start_listeners?, true) do
      Enum.concat(children, [Wayfarer.Listener.Supervisor])
    else
      children
    end
  end
end
