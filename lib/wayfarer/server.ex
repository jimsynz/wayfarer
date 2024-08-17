defmodule Wayfarer.Server do
  alias Spark.Options
  alias Wayfarer.{Dsl, Listener, Router, Server, Target}
  use GenServer
  require Logger

  @callback child_spec(keyword()) :: Supervisor.child_spec()
  @callback start_link(keyword()) :: GenServer.on_start()

  @scheme_type {:in, [:http, :https, :ws, :wss]}
  @port_type {:in, 0..0xFFFF}
  @transport_type {:in, [:http1, :http2, :auto]}
  @ip_type {:or,
            [
              {:tuple, [{:in, 0..0xFF}, {:in, 0..0xFF}, {:in, 0..0xFF}, {:in, 0..0xFF}]},
              {:tuple,
               [
                 {:in, 0..0xFFFF},
                 {:in, 0..0xFFFF},
                 {:in, 0..0xFFFF},
                 {:in, 0..0xFFFF},
                 {:in, 0..0xFFFF},
                 {:in, 0..0xFFFF},
                 {:in, 0..0xFFFF},
                 {:in, 0..0xFFFF}
               ]},
              {:struct, IP.Address}
            ]}

  @options_schema [
    module: [
      type: {:behaviour, __MODULE__},
      required: true,
      doc: "The name of the module which \"uses\" Wayfarer.Server."
    ],
    targets: [
      type: {:list, {:keyword_list, Dsl.Target.schema()}},
      required: false,
      default: [],
      doc: "A list of target specifications."
    ],
    listeners: [
      type: {:list, {:keyword_list, Dsl.Listener.schema()}},
      required: false,
      default: [],
      doc: "A list of listener specifications."
    ],
    routing_table: [
      type:
        {:list,
         {:tuple,
          [
            {:tuple, [@scheme_type, @ip_type, @port_type]},
            {:tuple, [@scheme_type, @ip_type, @port_type, @transport_type]},
            {:list, :string},
            {:in, [:round_robin, :sticky, :random, :least_connections]}
          ]}},
      required: false,
      default: [],
      doc: "A list of routes to add when the server starts."
    ]
  ]

  @moduledoc """
  A GenServer which manages a proxy.

  An appropriate `child_spec/1` and `start_link/1` are generated when `use
  Wayfarer.Server` is called.

  You can use this module directly if you are not planning on using the configuration DSL at all.

  ## Example

  ```elixir
  defmodule MyProxy do
    use Wayfarer.Server, targets: [..], listeners: [..], routing_table: [..]
  end
  ```

  ## Options

  #{Options.docs(@options_schema)}
  """

  @type options :: keyword

  @doc false
  @spec __using__(any) :: Macro.output()
  defmacro __using__(opts) do
    quote do
      @behaviour Server

      @doc false
      @spec child_spec(keyword) :: Supervisor.child_spec()
      def child_spec(opts) do
        opts =
          unquote(opts)
          |> Keyword.merge(opts)
          |> Keyword.put(:module, __MODULE__)

        Server.child_spec(opts)
      end

      @doc false
      @spec start_link(keyword) :: GenServer.on_start()
      def start_link(opts) do
        opts =
          unquote(opts)
          |> Keyword.merge(opts)
          |> Keyword.put(:module, __MODULE__)

        Server.start_link(opts)
      end

      defoverridable child_spec: 1, start_link: 1
    end
  end

  @doc false
  @spec target_status_change(
          {module, :http | :https, IP.Address.t(), :socket.port_number(),
           :http1 | :http2 | :auto},
          Router.health()
        ) :: :ok
  def target_status_change({module, scheme, address, port, transport}, status) do
    GenServer.cast(
      {:via, Registry, {Wayfarer.Server.Registry, module}},
      {:target_status_change, scheme, address, port, transport, status}
    )
  end

  @doc false
  @spec start_link(options) :: GenServer.on_start()
  def start_link(opts) do
    case Keyword.fetch(opts, :module) do
      {:ok, module} ->
        GenServer.start_link(__MODULE__, opts,
          name: {:via, Registry, {Wayfarer.Server.Registry, module}}
        )

      :error ->
        {:error, "Missing required `module` option."}
    end
  end

  @doc false
  @impl true
  @spec init(options) :: {:ok, map} | {:stop, any}
  def init(options) do
    with {:ok, options} <- Options.validate(options, @options_schema),
         {:ok, module} <- assert_is_server(options[:module]),
         listeners <- Keyword.get(options, :listeners, []),
         targets <- Keyword.get(options, :targets, []),
         initial_routing_table <- Keyword.get(options, :routing_table, []),
         {:ok, routing_table} <- Router.init(module),
         :ok <- Router.import_routes(routing_table, initial_routing_table),
         state <- %{module: module, routing_table: routing_table},
         {:ok, state} <- start_listeners(listeners, state),
         {:ok, state} <- start_targets(targets, state) do
      {:ok, state}
    else
      :error -> raise "unreachable"
      {:error, reason} -> {:stop, reason}
    end
  end

  @doc false
  @impl true
  @spec handle_cast(any, map) :: {:noreply, map}
  def handle_cast({:target_status_change, scheme, address, port, transport, status}, state) do
    Router.update_target_health_status(
      state.routing_table,
      {scheme, IP.Address.to_tuple(address), port, transport},
      status
    )

    {:noreply, state}
  end

  defp start_listeners(listeners, state) do
    listeners
    |> Enum.reduce_while({:ok, state}, fn listener, success ->
      listener = Keyword.put(listener, :module, state.module)

      case DynamicSupervisor.start_child(Listener.DynamicSupervisor, {Listener, listener}) do
        {:ok, pid} ->
          Process.link(pid)
          {:cont, success}

        {:error, {:already_started, pid}} ->
          Process.link(pid)
          {:cont, success}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp start_targets(targets, state) do
    targets
    |> Enum.reduce_while({:ok, state}, fn target, success ->
      target = Keyword.put(target, :module, state.module)

      case DynamicSupervisor.start_child(Target.DynamicSupervisor, {Target, target}) do
        {:ok, pid} ->
          Process.link(pid)
          {:cont, success}

        {:error, {:already_started, pid}} ->
          Process.link(pid)
          {:cont, success}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp assert_is_server(module) do
    if Spark.implements_behaviour?(module, __MODULE__) do
      {:ok, module}
    else
      {:error,
       "The module `#{inspect(module)}` does not implement the `Wayfarer.Server` behaviour."}
    end
  end
end
