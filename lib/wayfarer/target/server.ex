defmodule Wayfarer.Target.Server do
  alias Mint.HTTP
  alias Wayfarer.Target.Registry, as: TargetRegistry
  alias Wayfarer.Target.Table

  use GenServer, restart: :transient
  require Logger

  @options_schema NimbleOptions.new!(
                    scheme: [
                      type: {:in, [:http, :https]},
                      required: true,
                      doc: "The target's protocol"
                    ],
                    port: [
                      type: {:or, [nil, :pos_integer]},
                      required: true,
                      doc: "The target's listening port"
                    ],
                    ip: [
                      type:
                        {:or,
                         [
                           {:tuple, [:integer, :integer, :integer, :integer]},
                           {:tuple,
                            [
                              :integer,
                              :integer,
                              :integer,
                              :integer,
                              :integer,
                              :integer,
                              :integer,
                              :integer
                            ]},
                           {:tuple, [{:in, [:local]}, :string]}
                         ]},
                      required: true,
                      doc: "The target's IP address or domain socket"
                    ],
                    health_check: [
                      type: :keyword_list,
                      required: false,
                      keys: [
                        timeout: [
                          type: :pos_integer,
                          required: false,
                          default: :timer.seconds(5),
                          doc: "Health check connection timeout in milliseconds"
                        ],
                        interval: [
                          type: :pos_integer,
                          required: false,
                          default: :timer.seconds(5),
                          doc: "Health check interval in milliseconds"
                        ],
                        threshold: [
                          type: :pos_integer,
                          required: false,
                          default: 3,
                          doc: "Success threshold"
                        ],
                        path: [
                          type: :string,
                          required: false,
                          default: "/",
                          doc: "Health check endpoint"
                        ],
                        success_codes: [
                          type: {:or, [{:struct, Range}, {:list, {:struct, Range}}]},
                          required: false,
                          default: [200..299]
                        ]
                      ]
                    ]
                  )

  @default_health_check @options_schema.schema
                        |> get_in(~w[health_check keys]a)
                        |> Enum.map(fn {key, opts} -> {key, opts[:default]} end)

  @wayfarer_vsn Application.spec(:wayfarer)[:vsn]
  @elixir_vsn Application.spec(:elixir)[:vsn]
  @erlang_vsn :erlang.system_info(:otp_release)
  @mint_vsn Application.spec(:mint)[:vsn]

  @default_headers [
    {"User-Agent",
     "Wayfarer/#{@wayfarer_vsn} (Elixir #{@elixir_vsn}; Erlang #{@erlang_vsn}) Mint/#{@mint_vsn}"},
    {"Connection", "close"},
    {"Accept", "*/*"}
  ]

  @moduledoc """
  A GenServer which monitors the health of each target.

  ## Options

  #{NimbleOptions.docs(@options_schema)}
  """

  @type status :: :initial | :healthy | :unhealthy | :draining
  @type options :: [unquote(NimbleOptions.option_typespec(@options_schema))]
  @type state :: %{
          check: %{
            timeout: pos_integer(),
            interval: pos_integer(),
            threshold: pos_integer(),
            path: Path.t(),
            success_codes: [100..599]
          },
          conn: HTTP.t(),
          status: status,
          success_count: non_neg_integer(),
          target: %{
            ip: :inet.ip_address(),
            port: :inet.port_number(),
            scheme: :http | :https
          },
          url: String.t()
        }

  @doc false
  @spec start_link(options) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @doc false
  @impl true
  @spec init(options) :: {:ok, state, {:continue, :health_check}} | {:stop, any}
  def init(options) do
    with {:ok, options} <- NimbleOptions.validate(options, @options_schema),
         {:ok, _} <-
           Registry.register(
             TargetRegistry,
             {options[:scheme], options[:ip], options[:port]},
             nil
           ) do
      target = options |> Keyword.take(~w[scheme ip port]a) |> Map.new()

      check =
        options
        |> Keyword.get(:health_check, @default_health_check)
        |> Map.new()
        |> Map.update!(:success_codes, &List.wrap/1)

      state =
        %{
          target: target,
          check: check,
          status: :initial,
          success_count: 0,
          conn: nil,
          url: generate_url(target.scheme, target.ip, target.port, check.path)
        }

      Table.set_status(target.scheme, target.ip, target.port, :initial)

      {:ok, state, {:continue, :health_check}}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @doc false
  @impl true
  @spec handle_continue(:health_check, state) :: {:noreply, state}
  def handle_continue(:health_check, state) do
    state =
      state
      |> perform_health_check()

    {:noreply, state}
  end

  @doc false
  @impl true
  @spec handle_info(any, state) :: {:noreply, state}
  def handle_info(:health_check, state) when is_nil(state.conn) do
    state =
      state
      |> perform_health_check()

    {:noreply, state}
  end

  def handle_info(message, state) when not is_nil(state.conn) do
    state =
      case Mint.HTTP.stream(state.conn, message) do
        {:ok, conn, responses} ->
          Enum.reduce_while(responses, state, fn
            {:status, _, status}, state ->
              state =
                state
                |> drop_conn()
                |> handle_status(status)
                |> queue_next_check()

              {:halt, state}

            _, state ->
              {:cont, %{state | conn: conn}}
          end)

        {:error, _conn, error, _} ->
          state
          |> fail_state(error)
          |> queue_next_check()

        :unknown ->
          state
      end

    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp perform_health_check(state) when is_nil(state.conn) do
    address = "#{:inet.ntoa(state.target.ip)}"

    with {:ok, conn} <- HTTP.connect(state.target.scheme, address, state.target.port),
         {:ok, headers} <- generate_request_headers(address, state.target.port),
         {:ok, conn, _} <- HTTP.request(conn, "GET", state.check.path, headers, nil) do
      %{state | conn: conn}
    else
      {:error, reason} ->
        state
        |> fail_state(reason)
        |> queue_next_check()

      {:error, _conn, reason} ->
        state
        |> fail_state(reason)
        |> queue_next_check()
    end
  end

  defp generate_request_headers(address, port) do
    {:ok, [{"Host", "#{address}:#{port}"} | @default_headers]}
  end

  defp handle_status(state, status) do
    success? = Enum.any?(state.check.success_codes, &Enum.member?(&1, status))

    if success? do
      state
      |> increment_counter()
      |> next_success_state()
    else
      state
      |> fail_state("HTTP Status #{status}")
    end
  end

  defp fail_state(state, reason) do
    fail_warning(state, reason)

    state
    |> drop_conn()
    |> zero_counter()
    |> next_fail_state()
  end

  defp fail_warning(state, %{reason: reason}), do: fail_warning(state, reason)

  defp fail_warning(state, reason) when state.status not in [:unhealthy, :initial],
    do: Logger.warning("Target #{state.url} is now unhealthy: #{inspect(reason)}")

  defp fail_warning(_state, _reason), do: :ok

  defp drop_conn(state) when is_nil(state.conn), do: state

  defp drop_conn(state) do
    HTTP.close(state.conn)
    %{state | conn: nil}
  end

  defp next_fail_state(state) when state.status == :initial, do: state

  defp next_fail_state(state) when state.status != :unhealthy do
    Table.set_status(state.target.scheme, state.target.ip, state.target.port, :unhealthy)

    %{state | status: :unhealthy}
  end

  defp next_fail_state(state), do: state

  defp generate_url(scheme, ip, port, path) when tuple_size(ip) == 8 do
    "#{scheme}://[#{:inet.ntoa(ip)}]:#{port}#{path}"
    |> URI.new!()
    |> to_string()
  end

  defp generate_url(scheme, ip, port, path) do
    "#{scheme}://#{:inet.ntoa(ip)}:#{port}#{path}"
    |> URI.new!()
    |> to_string()
  end

  defp queue_next_check(state) do
    Process.send_after(self(), :health_check, state.check.interval)
    state
  end

  defp zero_counter(state) when state.success_count == 0, do: state
  defp zero_counter(state), do: %{state | success_count: 0}

  defp increment_counter(state) when state.success_count == state.check.threshold, do: state
  defp increment_counter(state), do: %{state | success_count: state.success_count + 1}

  defp next_success_state(state)
       when state.success_count == state.check.threshold and state.status != :healthy do
    Logger.info("Target #{state.url} is now healthy")
    Table.set_status(state.target.scheme, state.target.ip, state.target.port, :healthy)

    %{state | status: :healthy}
  end

  defp next_success_state(state), do: state
end
