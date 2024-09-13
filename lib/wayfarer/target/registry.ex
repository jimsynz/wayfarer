defmodule Wayfarer.Target.Registry do
  @moduledoc """
  Functions for interacting with the Target registry.
  """
  alias Wayfarer.{Error.Target.NoSuchTarget, Target}

  @doc """
  Register the calling process as a target.
  """
  @spec register(Target.t()) :: :ok | {:error, any}
  def register(target) do
    key = registry_key(target)

    with {:ok, _pid} <- Registry.register(__MODULE__, key, target) do
      :ok
    end
  end

  @doc """
  List active targets for a server module.
  """
  @spec list_targets_for_module(module) :: [Target.t()]
  def list_targets_for_module(module) do
    # :ets.fun2ms(fn {{module, _scheme, _address, _port, _transport}, _pid, target} when module == :module -> target end)

    Registry.select(
      __MODULE__,
      [
        {{{:"$1", :"$2", :"$3", :"$4", :"$5"}, :"$6", :"$7"}, [{:==, :"$1", module}], [:"$7"]}
      ]
    )
  end

  @doc """
  Return the process ID of a registered target.
  """
  @spec get_pid(Target.t()) :: {:ok, pid} | {:error, any}
  def get_pid(target) do
    key = registry_key(target)

    case Registry.lookup(__MODULE__, key) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, NoSuchTarget.exception(target: target)}
    end
  end

  @doc false
  def registry_key(target),
    do: {target.module, target.scheme, target.address, target.port, target.transport}
end
