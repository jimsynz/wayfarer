defmodule Wayfarer.Target.ConnectionRecycler do
  @default_ttl 30
  @default_ttl_ms :timer.seconds(@default_ttl)
  @default_sweep_interval 5
  @default_sweep_interval_ms :timer.seconds(@default_sweep_interval)

  @moduledoc """
  A cache which recycles recently completed Mint connections rather than
  throwing them away.

  Unfortunately, we can't use a fixed-size pool for this job because we need the
  number of connections to be able to grow when there is heavy demand.

  When we need a connection we look in the cache, and if there is one available
  then we re-use it, however if there is not we create a new one and check it in
  to the cache when complete.

  By default we keep connections around for #{@default_ttl}s before discarding
  them.
  """
  use GenServer
  require Logger

  alias Mint.HTTP

  @type state :: %{table: :ets.tid(), timer: :timer.tref()}

  def checkout(scheme, address, port, hostname) do
    GenServer.call(
      {:via, PartitionSupervisor, {__MODULE__, {scheme, address, port, hostname}}},
      {:get_connection, scheme, address, port, hostname, self()}
    )
  end

  def checkin(scheme, address, port, hostname, mint) do
    if HTTP.open?(mint, :read_write) do
      GenServer.cast(
        {:via, PartitionSupervisor, {__MODULE__, {scheme, address, port, hostname}}},
        {:checkin, scheme, address, port, hostname, mint}
      )
    else
      :ok
    end
  end

  @doc false
  @spec start_link(any) :: GenServer.on_start()
  def start_link(arg), do: GenServer.start_link(__MODULE__, arg)

  @doc false
  @impl true
  @spec init(any) :: {:ok, state} | {:stop, any}
  def init(_) do
    case :timer.send_interval(@default_sweep_interval_ms, :tick) do
      {:ok, timer} ->
        table = :ets.new(__MODULE__, [:bag])

        {:ok, %{table: table, timer: timer}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @doc false
  @impl true
  @spec handle_info(:tick, state) :: {:noreply, state}
  def handle_info(:tick, state) do
    # :ets.fun2ms(fn {_, checked_in_time, _} when checked_in_time < 123 -> true end)

    # IO.puts(:ets.info(__MODULE__, :size))

    horizon = System.monotonic_time(:millisecond) - @default_ttl_ms
    match_spec = [{{:_, :"$1", :_}, [{:<, :"$1", horizon}], [true]}]

    :ets.select_delete(state.table, match_spec)

    {:noreply, state}
  end

  @doc false
  @impl true
  def handle_call({:get_connection, scheme, address, port, hostname, pid}, _from, state) do
    reply =
      with {:ok, mint} <- get_connection(state.table, scheme, address, port, hostname),
           {:ok, mint} <- HTTP.controlling_process(mint, pid) do
        HTTP.set_mode(mint, :active)
      end

    {:reply, reply, state}
  end

  @doc false
  @impl true
  def handle_cast({:checkin, scheme, address, port, hostname, mint}, state) do
    case HTTP.set_mode(mint, :passive) do
      {:ok, mint} ->
        :ets.insert_new(
          state.table,
          {{scheme, address, port, hostname}, System.monotonic_time(:millisecond), mint}
        )

      {:error, reason} ->
        Logger.debug("Error checking in #{inspect(reason)}")
    end

    {:noreply, state}
  end

  defp get_connection(table, scheme, address, port, hostname) do
    case select_connection(table, scheme, address, port, hostname) do
      {:ok, mint} ->
        Logger.debug("Reusing connection #{inspect(mint)}")
        {:ok, mint}

      :error ->
        Logger.debug("Creating new connection #{inspect({scheme, address, port, hostname})}")
        HTTP.connect(scheme, address, port, hostname: hostname, timeout: 5000)
    end
  end

  defp select_connection(table, scheme, address, port, hostname) do
    # :ets.fun2ms(fn {{:http, {127, 0, 0, 1}, 80, "example.com"}, check_in_time, mint}
    #                when check_in_time >= 123 ->
    #   {check_in_time, mint}
    # end)

    horizon = System.monotonic_time(:millisecond) - @default_ttl_ms

    match_spec = [
      {{{scheme, address, port, hostname}, :"$1", :"$2"}, [{:>=, :"$1", horizon}],
       [{{:"$1", :"$2"}}]}
    ]

    case :ets.select(table, match_spec, 1) do
      {[{checked_in_at, mint} | _], _} ->
        :ets.delete_object(
          table,
          {{scheme, address, port, hostname}, checked_in_at, mint}
        )

        if HTTP.open?(mint, :read_write) do
          {:ok, mint}
        else
          select_connection(table, scheme, address, port, hostname)
        end

      _ ->
        :error
    end
  end
end
