defmodule Wayfarer.Listener do
  @moduledoc """
  Manage HTTP listeners.
  """

  alias Wayfarer.Listener.DynamicSupervisor, as: ListenerSupervisor
  alias Wayfarer.Listener.Registry, as: ListenerRegistry
  alias Wayfarer.Listener.Server

  @doc """
  Start listener.
  """
  @spec start_listener(Server.options()) :: Supervisor.on_start_child()
  def start_listener(options),
    do: DynamicSupervisor.start_child(ListenerSupervisor, {Server, options})

  @doc """
  Stop listener
  """
  @spec stop_listener(:inet.socket_address(), :inet.port_number()) :: :ok
  def stop_listener(ip, port),
    do: GenServer.stop({:via, Registry, {ListenerRegistry, {ip, port}}}, :normal)
end
