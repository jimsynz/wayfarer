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
  @spec stop_listener(:http | :https, :inet.socket_address(), :inet.port_number()) :: :ok
  def stop_listener(scheme, ip, port),
    do: GenServer.stop({:via, Registry, {ListenerRegistry, {scheme, ip, port}}}, :normal)
end
