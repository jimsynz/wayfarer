defmodule Wayfarer.Dsl.Target do
  @moduledoc """
  A struct for storing a target generated by the DSL.
  """

  alias Spark.{Dsl.Entity, Options}
  alias Wayfarer.Dsl.{HealthCheck, HealthChecks}
  alias Wayfarer.Utils

  defstruct address: nil,
            health_checks: HealthChecks.init(),
            module: nil,
            name: nil,
            port: nil,
            scheme: :http,
            transport: :auto,
            uri: nil

  @type t :: %__MODULE__{
          address: IP.Address.t(),
          health_checks: HealthChecks.t(),
          module: nil | module,
          name: nil | String.t(),
          port: :inet.port_number(),
          scheme: :http | :https | :plug | :ws | :wss,
          transport: :http1 | :http2 | :auto,
          uri: URI.t()
        }

  @shared_schema [
    address: [
      type: {:or, [{:struct, IP.Address}, :string]},
      required: true,
      doc: "The address of the interface to listen on."
    ],
    name: [
      type: {:or, [nil, :string]},
      required: false,
      doc: "A unique name for the target (defaults to the URI)."
    ],
    port: [
      type: :pos_integer,
      required: true,
      doc: "The TCP port on which to listen for incoming connections."
    ],
    transport: [
      type: {:in, [:http1, :http2, :auto]},
      required: false,
      default: :auto,
      doc: "Which HTTP protocol to use."
    ]
  ]

  @doc false
  @spec entities :: [Entity.t()]
  def entities do
    [
      %Entity{
        name: :http,
        target: __MODULE__,
        schema: @shared_schema,
        auto_set_fields: [scheme: :http],
        args: [:address, :port],
        imports: [IP.Sigil],
        transform: {__MODULE__, :transform, []},
        entities: [health_checks: HealthChecks.entities()],
        singleton_entity_keys: [:health_checks]
      },
      %Entity{
        name: :https,
        target: __MODULE__,
        schema: @shared_schema,
        auto_set_fields: [scheme: :https],
        args: [:address, :port],
        imports: [IP.Sigil],
        transform: {__MODULE__, :transform, []},
        entities: [health_checks: HealthChecks.entities()],
        singleton_entity_keys: [:health_checks]
      },
      %Entity{
        name: :plug,
        target: __MODULE__,
        schema: [
          module: [
            type: {:spark_behaviour, Plug},
            doc: "A plug which can handle requests.",
            required: true
          ]
        ],
        auto_set_fields: [scheme: :plug],
        args: [:module]
      },
      %Entity{
        name: :ws,
        target: __MODULE__,
        schema: @shared_schema,
        auto_set_fields: [scheme: :ws],
        args: [:address, :port],
        imports: [IP.Sigil],
        transform: {__MODULE__, :transform, []},
        entities: [health_checks: HealthChecks.entities()],
        singleton_entity_keys: [:health_checks]
      },
      %Entity{
        name: :wss,
        target: __MODULE__,
        schema: @shared_schema,
        auto_set_fields: [scheme: :wss],
        args: [:address, :port],
        imports: [IP.Sigil],
        transform: {__MODULE__, :transform, []},
        entities: [health_checks: HealthChecks.entities()],
        singleton_entity_keys: [:health_checks]
      }
    ]
  end

  @doc false
  @spec transform(t) :: {:ok, t} | {:error, any}
  def transform(target) do
    with {:ok, target} <- ensure_health_checks(target),
         {:ok, target} <- maybe_parse_address(target),
         {:ok, target} <- set_uri(target) do
      maybe_set_name(target)
    end
  end

  @doc false
  def schema do
    @shared_schema
    |> Options.Helpers.make_optional!(:address)
    |> Options.Helpers.make_optional!(:port)
    |> Keyword.merge(
      scheme: [
        type: {:in, [:http, :https, :plug, :ws, :wss]},
        required: true,
        doc: "The connection type for the target."
      ],
      plug: [
        type: {:behaviour, Plug},
        required: false,
        doc: "A plug to use when `scheme` is `:plug`."
      ],
      health_checks: [
        type: {:list, {:keyword_list, HealthCheck.schema()}},
        required: false,
        default: [],
        doc: "A list of health check configurations."
      ]
    )
  end

  defp ensure_health_checks(target) when is_nil(target.health_checks),
    do: {:ok, %{target | health_checks: HealthChecks.init()}}

  defp ensure_health_checks(target), do: {:ok, target}

  defp maybe_parse_address(target) when is_struct(target.address, IP.Address),
    do: {:ok, target}

  defp maybe_parse_address(target) when is_binary(target.address) do
    with {:ok, address} <- IP.Address.from_string(target.address) do
      {:ok, %{target | address: address}}
    end
  end

  defp maybe_parse_address(target) when is_nil(target.address), do: {:ok, target}

  defp set_uri(target) when target.scheme == :plug do
    uri = %URI{
      scheme: "plug",
      host: inspect(target.module)
    }

    {:ok, %{target | uri: uri}}
  end

  defp set_uri(target) do
    with {:ok, uri} <- Utils.to_uri(target.scheme, target.address, target.port) do
      {:ok, %{target | uri: uri}}
    end
  end

  defp maybe_set_name(target) when is_binary(target.name), do: {:ok, target}
  defp maybe_set_name(target), do: {:ok, %{target | name: to_string(target.uri)}}
end
