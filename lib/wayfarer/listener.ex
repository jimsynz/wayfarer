defmodule Wayfarer.Listener do
  # @moduledoc ⬇️⬇️

  use GenServer, restart: :transient
  require Logger
  alias Spark.Options
  import Wayfarer.Utils

  @options_schema [
    scheme: [
      type: {:in, [:http, :https]},
      doc: "The connection protocol.",
      required: true
    ],
    port: [
      type: {:in, 1..0xFFFF},
      doc: "The TCP port to listen on for connections.",
      required: true
    ],
    address: [
      type: {:struct, IP.Address},
      doc: "The IP address of an interface to bind to.",
      required: true
    ],
    drain_timeout: [
      type: :pos_integer,
      doc: "How long to wait for existing connections to complete on shutdown.",
      required: false,
      default: :timer.seconds(60)
    ],
    module: [
      type: {:behaviour, Wayfarer.Server},
      doc: "The proxy module this listener is linked to.",
      required: true
    ],
    name: [
      type: {:or, [:string, nil]},
      doc: "An optional name for the listener.",
      required: false
    ],
    keyfile: [
      type: {:or, [:string, nil]},
      doc: "The path to the SSL secret key file.",
      required: false,
      subsection: "HTTPS Options"
    ],
    certfile: [
      type: {:or, [:string, nil]},
      doc: "The path to the SSL certificate file",
      required: false,
      subsection: "HTTPS Options"
    ],
    cipher_suite: [
      type: {:in, [nil, :strong, :compatible]},
      doc:
        "Used to define a pre-selected set of ciphers, as described by `Plug.SSL.configure/1.`",
      required: false,
      subsection: "HTTPS Options"
    ],
    http_1_options: [
      type: :keyword_list,
      doc: "See `t:Bandit.http_1_options/0`.",
      required: false,
      subsection: "Protocol-specific Options"
    ],
    http_2_options: [
      type: :keyword_list,
      doc: "See `t:Bandit.http_2_options/0`.",
      required: false,
      subsection: "Protocol-specific Options"
    ],
    websocket_options: [
      type: :keyword_list,
      doc: "See `t:Bandit.websocket_options/0`.",
      required: false,
      subsection: "Protocol-specific Options"
    ],
    thousand_island_options: [
      type: :keyword_list,
      doc: "See `t:ThousandIsland.options/0`",
      subsection: "Protocol-specific Options"
    ]
  ]

  @moduledoc """
  A GenServer which manages the state of each Bandit listener.

  You should not need to create one of these yourself, instead use it via
  `Wayfarer.Server`.

  ## Options

  #{Options.docs(@options_schema)}
  """

  @doc false
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @doc false
  @impl true
  def init(options) do
    with {:ok, options} <- validate_options(options),
         bandit_options <- build_bandit_options(options),
         {:ok, pid} <- Bandit.start_link(bandit_options),
         {:ok, {listen_address, listen_port}} <- ThousandIsland.listener_info(pid),
         {:ok, listen_address} <- IP.Address.from_tuple(listen_address),
         {:ok, uri} <- to_uri(options[:scheme], listen_address, listen_port) do
      Logger.info("Started Wayfarer listener on #{uri}")

      {:ok, %{server: pid, name: options[:name], uri: uri}}
    else
      :error -> {:stop, "Unable to retrieve listener information."}
      {:error, reason} -> {:stop, reason}
    end
  end

  @doc false
  @impl true
  def terminate(:normal, %{server: server}) do
    GenServer.stop(server, :normal)
  end

  defp validate_options(options) do
    case Keyword.fetch(options, :scheme) do
      {:ok, :https} ->
        schema =
          @options_schema
          |> Options.Helpers.make_required!(:keyfile)
          |> Options.Helpers.make_required!(:certfile)
          |> Options.Helpers.make_required!(:cipher_suite)

        Options.validate(options, schema)

      _ ->
        Options.validate(options, @options_schema)
    end
  end

  defp build_bandit_options(options) do
    plug_options = %{
      address: IP.Address.to_tuple(options[:address]),
      module: options[:module],
      port: options[:port],
      scheme: options[:scheme]
    }

    thousand_island_options =
      options
      |> Keyword.get(:thousand_island_options, [])
      |> Keyword.put_new(:shutdown_timeout, options[:drain_timeout])

    base_options = [
      ip: IP.Address.to_tuple(options[:address]),
      otp_app: Application.get_application(options[:module]),
      plug: {Wayfarer.Server.Plug, plug_options},
      port: options[:port],
      scheme: options[:scheme],
      thousand_island_options: thousand_island_options
    ]

    ssl_options =
      if options[:scheme] == :https do
        [
          certfile: options[:certfile],
          keyfile: options[:keyfile]
        ]
        |> maybe_add_option(:cipher_suite, options[:cipher_suite])
      else
        []
      end

    base_options
    |> Enum.concat(ssl_options)
    |> maybe_add_option(:http_1_options, options[:http_1_options])
    |> maybe_add_option(:http_2_options, options[:http_2_options])
    |> maybe_add_option(:websocket_options, options[:websocket_options])
  end

  defp maybe_add_option(options, _key, nil), do: options
  defp maybe_add_option(options, key, value), do: Keyword.put(options, key, value)
end
