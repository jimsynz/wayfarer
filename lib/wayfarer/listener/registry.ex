defmodule Wayfarer.Listener.Registry do
  @moduledoc """
  Functions for interacting with the Listener registry.
  """
  alias Wayfarer.{
    Error.Listener.NoSuchListener,
    Listener
  }

  @doc """
  Register the calling process as a listener.
  """
  @spec register(Listener.t(), Listener.status()) :: :ok | {:error, any}
  def register(listener, status \\ :starting) do
    key = registry_key(listener)

    with {:ok, _pid} <- Registry.register(__MODULE__, key, {listener, status}) do
      :ok
    end
  end

  @doc """
  List active listeners for a server module.
  """
  @spec list_listeners_for_module(module) :: [Listener.t()]
  def list_listeners_for_module(module) do
    # :ets.fun2ms(fn {{module, _scheme, _address, _port}, _pid, {listener, _status}} when module == :module ->
    #   listener
    # end)

    Registry.select(
      __MODULE__,
      [
        {{{:"$1", :"$2", :"$3", :"$4"}, :"$5", {:"$6", :"$7"}}, [{:==, :"$1", module}], [:"$6"]}
      ]
    )
  end

  @doc """
  Return the status of a listener.
  """
  @spec get_status(Listener.t()) :: {:ok, Listener.status()} | {:error, any}
  def get_status(listener) do
    key = registry_key(listener)

    case Registry.lookup(__MODULE__, key) do
      [{_pid, {_listener, status}}] -> {:ok, status}
      [] -> {:error, NoSuchListener.exception(listener: listener)}
    end
  end

  @doc """
  Return the process ID of a registered listener.
  """
  @spec get_pid(Listener.t()) :: {:ok, pid} | {:error, any}
  def get_pid(listener) do
    key = registry_key(listener)

    case Registry.lookup(__MODULE__, key) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, NoSuchListener.exception(listener: listener)}
    end
  end

  @doc """
  Update the status of a listener.
  """
  @spec update_status(Listener.t(), Listener.status()) :: :ok | {:error, any}
  def update_status(listener, status) do
    key = registry_key(listener)

    case Registry.update_value(__MODULE__, key, fn {_listener, _status} -> {listener, status} end) do
      {_, _} -> :ok
      :error -> {:error, NoSuchListener.exception(listener: listener)}
    end
  end

  @doc """
  Returns the registry key for a listener.
  """
  @spec registry_key(Listener.t()) :: any
  def registry_key(listener),
    do: {listener.module, listener.scheme, listener.address, listener.port}
end
