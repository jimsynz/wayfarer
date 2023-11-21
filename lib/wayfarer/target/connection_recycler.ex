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

  alias Mint.HTTP

  @type state :: %{table: :ets.tid(), timer: :timer.tref()}

  def try_acquire(scheme, address, port, hostname) do
    if acquire_lock(scheme, address, port, hostname) do
      # :ets.fun2ms(fn {{:http, {127, 0, 0, 1}, 80, "example.com"}, check_in_time, mint}
      #                when check_in_time >= 123 ->
      #   {check_in_time, mint}
      # end)

      horizon = System.monotonic_time(:millisecond) - @default_ttl_ms

      match_spec = [
        {{{scheme, address, port, hostname}, :"$1", :"$2"}, [{:>=, :"$1", horizon}],
         [{{:"$1", :"$2"}}]}
      ]

      result =
        case :ets.select(__MODULE__, match_spec, 1) do
          {[{checked_in_at, mint} | _], _} ->
            :ets.delete_object(
              __MODULE__,
              {{scheme, address, port, hostname}, checked_in_at, mint}
            )

            release_lock(scheme, address, port, hostname)

            HTTP.controlling_process(mint, self())

          _ ->
            :error
            release_lock(scheme, address, port, hostname)
        end

      result
    else
      :error
    end
  end

  def checkin(scheme, address, port, hostname, mint) do
    pid =
      __MODULE__
      |> Process.whereis()

    case HTTP.controlling_process(mint, pid) |> dbg() do
      {:ok, mint} ->
        :ets.insert(
          __MODULE__,
          {{scheme, address, port, hostname}, System.monotonic_time(:millisecond), mint}
        )

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  @spec start_link(any) :: GenServer.on_start()
  def start_link(arg), do: GenServer.start_link(__MODULE__, arg, name: __MODULE__)

  @doc false
  @impl true
  @spec init(any) :: {:ok, state} | {:stop, any}
  def init(_) do
    case :timer.send_interval(@default_sweep_interval_ms, :tick) do
      {:ok, timer} ->
        table =
          __MODULE__
          |> :ets.new([
            :public,
            :named_table,
            :bag,
            read_concurrency: true,
            write_concurrency: true
          ])

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

    IO.puts(:ets.info(__MODULE__, :size))

    horizon = System.monotonic_time(:millisecond) - @default_ttl_ms
    match_spec = [{{:_, :"$1", :_}, [{:<, :"$1", horizon}], [true]}]

    :ets.select_delete(state.table, match_spec)

    {:noreply, state}
  end

  defp acquire_lock(scheme, address, port, hostname, remaining \\ 15)

  defp acquire_lock(_scheme, _address, _port, _hostname, 0), do: false

  defp acquire_lock(scheme, address, port, hostname, remaining) do
    if Semaphore.acquire({__MODULE__, scheme, address, port, hostname}, 1) do
      true
    else
      acquire_lock(scheme, address, port, hostname, remaining - 1)
    end
  end

  defp release_lock(scheme, address, port, hostname) do
    Semaphore.release({__MODULE__, scheme, address, port, hostname})
  end
end
