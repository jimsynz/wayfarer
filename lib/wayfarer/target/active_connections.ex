defmodule Wayfarer.Target.ActiveConnections do
  @moduledoc """
  A simple ETS table that tracks active connections to a given target.
  """

  use GenServer
  require Logger
  alias Wayfarer.{Router, Utils}

  @type state :: %{table: :ets.tid(), timer: :timer.tref()}

  @doc false
  @spec start_link(any) :: GenServer.on_start()
  def start_link(arg), do: GenServer.start_link(__MODULE__, arg, name: __MODULE__)

  @doc false
  @impl true
  @spec init(any) :: {:ok, state} | {:stop, any}
  def init(_) do
    report_interval()
    |> :timer.send_interval(:tick)
    |> case do
      {:ok, timer} ->
        table =
          __MODULE__
          |> :ets.new([:public, :named_table, :duplicate_bag])

        {:ok, %{table: table, timer: timer}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @doc false
  @impl true
  @spec handle_info(:tick | {:DOWN, any, :process, any, pid, any}, state) :: {:noreply, state}
  def handle_info(:tick, state) do
    size = :ets.info(state.table, :size)
    Logger.debug("Active connections: #{size}")

    {:noreply, state}
  end

  def handle_info({:DOWN, _, :process, pid, _}, state) do
    :ets.match_delete(__MODULE__, {:_, pid, :_})
    {:noreply, state}
  end

  @doc false
  @impl true
  @spec handle_cast({:monitor, pid}, state) :: {:noreply, state}
  def handle_cast({:monitor, pid}, state) do
    Process.monitor(pid)
    {:noreply, state}
  end

  @doc """
  Track a new active connection.
  """
  @spec connect(Router.target()) :: :ok
  def connect(target) do
    :ets.insert(__MODULE__, {target, self(), System.monotonic_time()})
    GenServer.cast(__MODULE__, {:monitor, self()})
  end

  @doc """
  Remove an inactive connection.
  """
  @spec disconnect(Router.target()) :: :ok
  def disconnect(target) do
    :ets.match_delete(__MODULE__, {target, self(), :_})
    :ok
  end

  @doc """
  Return the request count for each of the named targets.
  """
  @spec request_count(Router.target() | [Router.target()]) :: %{
          Router.target() => non_neg_integer()
        }
  def request_count(targets) do
    # :ets.fun2ms(fn {target, _, _} when target in [:targeta, :targetb] -> target end)

    targets = List.wrap(targets)
    target_guard = Utils.targets_to_ms_guard(:"$1", targets)
    match_spec = [{{:"$1", :_, :_}, target_guard, [:"$1"]}]

    __MODULE__
    |> :ets.select(match_spec)
    |> Enum.frequencies()
  end

  @doc """
  Return the most recent request time for the named targets.
  """
  @spec last_request_time([Router.target()]) :: %{Router.target() => non_neg_integer()}
  def last_request_time(targets) do
    # :ets.fun2ms(fn {target, _, t} when target in [:targeta, :targetb] -> {target, t} end)

    target_guard = Utils.targets_to_ms_guard(:"$1", targets)
    match_spec = [{{:"$1", :_, :"$2"}, target_guard, [{{:"$1", :"$2"}}]}]

    __MODULE__
    |> :ets.select(match_spec)
    |> most_recent_request_time_per_target()
  end

  defp most_recent_request_time_per_target(target_times),
    do: most_recent_request_time_per_target(target_times, %{})

  defp most_recent_request_time_per_target([{target, time} | tail], result)
       when time <= :erlang.map_get(target, result),
       do: most_recent_request_time_per_target(tail, result)

  defp most_recent_request_time_per_target([{target, time} | tail], result),
    do: most_recent_request_time_per_target(tail, Map.put(result, target, time))

  defp most_recent_request_time_per_target([], result), do: result

  defp report_interval do
    :wayfarer
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:report_interval, :timer.seconds(1))
  end
end
