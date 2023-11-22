defmodule Wayfarer.Target.TotalConnections do
  @moduledoc """
  A simple ETS table that tracks the total number of requests for each target.
  """

  use GenServer
  alias Wayfarer.{Router, Utils}
  require Logger

  @type state :: %{table: :ets.tid(), timer: :timer.tref()}

  @doc """
  Increment the proxy connection counter for the specified target.
  """
  @spec proxy_connect(Router.target()) :: :ok
  def proxy_connect(target) do
    :ets.update_counter(__MODULE__, target, {2, 1}, {target, 0, 0})

    :ok
  end

  @doc """
  Increment the health check connection counter for the specified target.
  """
  @spec health_check_connect(Router.target()) :: :ok
  def health_check_connect(target) do
    :ets.update_counter(__MODULE__, target, {3, 1}, {target, 0, 0})

    :ok
  end

  @doc """
  Return the total number of requests for the provided targets.
  """
  @spec request_count(Router.target() | [Router.target()]) :: %{
          Router.target() => %{proxied: non_neg_integer(), health_checks: non_neg_integer()}
        }
  def request_count(targets) do
    # :ets.fun2ms(fn {target, proxied, checks} when target in [:a, :b] -> {target, proxied, checks} end)

    targets = List.wrap(targets)
    target_guard = Utils.targets_to_ms_guard(:"$1", targets)

    match_spec = [
      {{:"$1", :"$2", :"$3"}, target_guard, [{{:"$1", :"$2", :"$3"}}]}
    ]

    __MODULE__
    |> :ets.select(match_spec)
    |> Map.new(fn {target, proxied, checks} ->
      {target, %{proxied: proxied, health_checks: checks}}
    end)
  end

  @doc """
  Return the total number of proxy requests for the provided targets.
  """
  @spec proxy_count(Router.target() | [Router.target()]) :: %{
          Router.target() => non_neg_integer()
        }
  def proxy_count(targets) do
    # :ets.fun2ms(fn {target, proxied, _} when target in [:a, :b] -> {target, proxied} end)

    targets = List.wrap(targets)
    target_guard = Utils.targets_to_ms_guard(:"$1", targets)
    match_spec = [{{:"$1", :"$2", :_}, target_guard, [{{:"$1", :"$2"}}]}]

    __MODULE__
    |> :ets.select(match_spec)
    |> Map.new()
  end

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
          |> :ets.new([:public, :named_table, :set])

        {:ok, %{table: table, timer: timer}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  @spec handle_info(:tick, state) :: {:noreply, state}
  def handle_info(:tick, state) do
    # for {target, count} <- :ets.tab2list(state.table) do
    #   Logger.debug("Total connections for #{inspect(target)}: #{count}")
    # end

    {:noreply, state}
  end

  defp report_interval do
    :wayfarer
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:report_interval, :timer.seconds(10))
  end
end
