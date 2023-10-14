defmodule Wayfarer.Target do
  @moduledoc """
  Manage HTTP targets.
  """

  alias Wayfarer.Target.DynamicSupervisor, as: TargetSupervisor
  alias Wayfarer.Target.Registry, as: TargetRegistry
  alias Wayfarer.Target.Server

  @doc """
  Start target.
  """
  @spec start_target(Server.options()) :: Supervisor.on_start_child()
  def start_target(options),
    do: DynamicSupervisor.start_child(TargetSupervisor, {Server, options})

  @doc """
  Stop target
  """
  @spec stop_target(:inet.socket_address(), :inet.port_number()) :: :ok
  def stop_target(ip, port),
    do: GenServer.stop({:via, Registry, {TargetRegistry, {ip, port}}}, :normal)
end
