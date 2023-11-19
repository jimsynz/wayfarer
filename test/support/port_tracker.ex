defmodule Support.PortTracker do
  @moduledoc """
  Generates port numbers which aren't currently being used by any processes.
  """

  use GenServer
  require Logger

  defmacro __using__(_) do
    quote do
      defp random_port(opts \\ []) do
        unquote(__MODULE__).allocate(opts)
      end
    end
  end

  @doc false
  @spec start_link(any) :: GenServer.on_start()
  def start_link(arg), do: GenServer.start_link(__MODULE__, arg, name: __MODULE__)

  @doc false
  @impl true
  def init(_) do
    table = :ets.new(__MODULE__, [:public, :named_table, :set])
    {:ok, table}
  end

  @doc false
  @impl true
  def handle_cast({:monitor, pid}, table) do
    Process.monitor(pid)
    {:noreply, table}
  end

  @doc false
  @impl true
  def handle_info({:DOWN, _, :process, pid, _}, table) do
    :ets.match_delete(table, {:_, pid})
    {:noreply, table}
  end

  @doc """
  Allocate an unused random port between `min_port` and `max_port`.
  """
  def allocate(opts) do
    port = random_port(opts)

    if :ets.insert_new(__MODULE__, {port, self()}) do
      GenServer.cast(__MODULE__, {:monitor, self()})
      port
    else
      allocate(opts)
    end
  end

  defp random_port(opts) do
    max_port = Keyword.get(opts, :max_port, 0xFFFF)
    min_port = Keyword.get(opts, :min_port, 20_000)
    :rand.uniform(max_port - min_port) + min_port
  end
end
