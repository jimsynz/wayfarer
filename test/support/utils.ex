defmodule Support.Utils do
  @moduledoc false

  import Wayfarer.Utils

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
    end
  end

  def wait_for_target_state({module, scheme, address, port}, state) do
    with {:ok, scheme} <- sanitise_scheme(scheme),
         {:ok, address} <- sanitise_ip_address(address),
         {:ok, port} <- sanitise_port(port) do
      do_wait_for_target_state({module, scheme, IP.Address.from_tuple!(address), port}, state, 10)
    end
  end

  defp do_wait_for_target_state(key, state, 0) do
    case Wayfarer.Target.current_status(key) do
      {:ok, ^state} ->
        :ok

      {:ok, _} ->
        {:error, "Target never reached state #{inspect(state)}"}

      {:error, reason} ->
        raise reason
    end
  end

  defp do_wait_for_target_state(key, state, iterations_left) do
    case Wayfarer.Target.current_status(key) do
      {:ok, ^state} ->
        :ok

      {:ok, _} ->
        Process.sleep(100)
        do_wait_for_target_state(key, state, iterations_left - 1)

      {:error, reason} ->
        raise reason
    end
  catch
    :exit, {:noproc, _} ->
      Process.sleep(100)
      do_wait_for_target_state(key, state, iterations_left - 1)
  end
end
