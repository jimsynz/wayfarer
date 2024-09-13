defmodule Wayfarer.Target do
  # @moduledoc ⬇️⬇️

  defstruct [:scheme, :port, :address, :module, :name, :transport]

  use GenServer, restart: :transient
  require Logger
  alias Spark.Options
  alias Wayfarer.{Dsl.HealthCheck, Router, Server, Target}
  import Wayfarer.Utils

  @options_schema [
    scheme: [
      type: {:in, [:http, :https, :ws, :wss]},
      doc: "The connection scheme.",
      required: true
    ],
    port: [
      type: {:in, 1..0xFFFF},
      doc: "The TCP port to connect to.",
      required: true
    ],
    address: [
      type: {:struct, IP.Address},
      doc: "The IP address to connect to.",
      required: true
    ],
    module: [
      type: {:behaviour, Wayfarer.Server},
      doc: "The proxy module this target is linked to.",
      required: true
    ],
    name: [
      type: {:or, [nil, :string]},
      doc: "An optional name for the target.",
      required: false
    ],
    transport: [
      type: {:in, [:http1, :http2, :auto]},
      required: false,
      default: :auto,
      doc: "The connection protocol."
    ],
    health_checks: [
      type: {:list, {:keyword_list, HealthCheck.schema()}},
      required: false,
      default: HealthCheck.default() |> HealthCheck.to_options() |> then(&[&1])
    ]
  ]

  @wayfarer_vsn Application.spec(:wayfarer, :vsn) || Mix.Project.config()[:version]
  @elixir_vsn Application.spec(:elixir, :vsn)
  @erlang_vsn :erlang.system_info(:otp_release)
  @mint_vsn Application.spec(:mint, :vsn)

  @default_headers [
    {"User-Agent",
     "Wayfarer/#{@wayfarer_vsn} (Elixir #{@elixir_vsn}; Erlang #{@erlang_vsn}) Mint/#{@mint_vsn}"},
    {"Connection", "close"},
    {"Accept", "*/*"}
  ]

  @type t :: %__MODULE__{
          scheme: :http | :https | :ws | :wss,
          port: :socket.port_number(),
          address: IP.Address.t(),
          module: module,
          name: nil | String.t(),
          transport: :http1 | :http2 | :auto
        }

  @moduledoc """
  A GenServer responsible for performing health-checks against HTTP and HTTPS
  targets.

  You should not need to create one of these yourself, instead use it via
  `Wayfarer.Server`.

  ## Options

  #{Options.docs(@options_schema)}
  """

  @type key :: {module, :http | :https, IP.Address.t(), :socket.port_number()}

  @doc false
  def schema, do: @options_schema

  @doc false
  @spec check_failed({key, reference}) :: :ok
  def check_failed({key, id}),
    do: GenServer.cast({:via, Registry, {Wayfarer.Target.Registry, key}}, {:check_failed, id})

  @doc false
  @spec check_passed({key, reference}) :: :ok
  def check_passed({key, id}),
    do: GenServer.cast({:via, Registry, {Wayfarer.Target.Registry, key}}, {:check_passed, id})

  @doc "Return the current health status of the target"
  @spec current_status(pid | key) :: {:ok, Router.health()} | {:error, any}
  def current_status(pid) when is_pid(pid), do: GenServer.call(pid, :current_status)

  def current_status(key),
    do: GenServer.call({:via, Registry, {Wayfarer.Target.Registry, key}}, :current_status)

  @doc false
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @doc false
  @impl true
  def init(options) do
    with {:ok, options} <- Options.validate(options, @options_schema),
         {:ok, uri} <- to_uri(options[:scheme], options[:address], options[:port]) do
      target = struct(__MODULE__, options)
      module = options[:module]

      key = Target.Registry.registry_key(target)

      checks =
        options
        |> Keyword.get(:health_checks, [])
        |> Map.new(fn check ->
          id = make_ref()

          check =
            check
            |> Map.new()
            |> Map.merge(%{
              status: :initial,
              scheme: target.scheme,
              address: IP.Address.to_tuple(target.address),
              port: target.port,
              uri: %{uri | path: check[:path]},
              id: id,
              ref: {key, id},
              method: check[:method] |> to_string() |> String.upcase(),
              headers: @default_headers,
              hostname: check[:hostname] || uri.host,
              transport: target.transport,
              passes: 0
            })

          {id, check}
        end)

      Logger.info("Starting Wayfarer target #{uri}.")

      state = %{
        target: target,
        checks: checks,
        uri: uri,
        module: module,
        name: options[:name],
        status: :initial,
        key: key
      }

      Target.Registry.register(target)

      {:ok, state, {:continue, :perform_health_checks}}
    end
  end

  @doc false
  @impl true
  def handle_continue(:perform_health_checks, state) do
    perform_health_checks(state)
    {:noreply, state}
  end

  @doc false
  @impl true
  def handle_cast({:check_failed, id}, state)
      when is_map_key(state.checks, id) and state.status == :unhealthy do
    checks =
      Map.update!(state.checks, id, fn check ->
        check
        |> queue_check()
        |> then(&%{&1 | status: :unhealthy, passes: 0})
      end)

    {:noreply, %{state | checks: checks}}
  end

  def handle_cast({:check_failed, id}, state) when is_map_key(state.checks, id) do
    checks =
      Map.update!(state.checks, id, fn check ->
        check
        |> queue_check()
        |> then(&%{&1 | status: :unhealthy, passes: 0})
      end)

    Server.target_status_change(state.key, :unhealthy)

    {:noreply, %{state | checks: checks, status: :unhealthy}}
  end

  def handle_cast({:check_passed, id}, state) when state.status == :healthy do
    check =
      state.checks
      |> Map.fetch!(id)
      |> queue_check()
      |> increment_success()

    checks = Map.put(state.checks, id, check)

    {:noreply, %{state | checks: checks}}
  end

  def handle_cast({:check_passed, id}, state) when is_map_key(state.checks, id) do
    check =
      state.checks
      |> Map.fetch!(id)
      |> queue_check()
      |> increment_success()

    checks = Map.put(state.checks, id, check)

    target_became_healthy? =
      checks
      |> Map.values()
      |> Enum.all?(&(&1.status == :healthy))

    if target_became_healthy? do
      Server.target_status_change(state.key, :healthy)

      Logger.info("Target #{state.uri} became healthy")

      {:noreply, %{state | checks: checks, status: :healthy}}
    else
      {:noreply, %{state | checks: checks}}
    end
  end

  def handle_cast(_message, state), do: {:noreply, state}

  @doc false
  @impl true
  def handle_info({:perform_check, id}, state) do
    check = Map.fetch!(state.checks, id)
    {:ok, _pid} = GenServer.start(Target.Check, check)
    {:noreply, state}
  end

  @doc false
  @impl true
  def handle_call(:current_status, _from, state) do
    {:reply, {:ok, state.status}, state}
  end

  defp perform_health_checks(state) do
    for {_ref, check} <- state.checks do
      {:ok, _pid} = GenServer.start(Target.Check, check)
    end
  end

  defp queue_check(check) do
    Process.send_after(self(), {:perform_check, check.id}, check.interval)
    check
  end

  defp increment_success(check), do: increment_success(check, check.passes + 1)

  defp increment_success(check, passes) when passes >= check.threshold,
    do: %{check | passes: passes, status: :healthy}

  defp increment_success(check, passes), do: %{check | passes: passes}
end
