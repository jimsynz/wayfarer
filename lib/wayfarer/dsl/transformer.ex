defmodule Wayfarer.Dsl.Transformer do
  @moduledoc """
  The Transformer for the Wayfarer DSL extension.
  """

  alias Spark.{Dsl, Dsl.Transformer, Error.DslError}
  alias Wayfarer.Dsl.{Config, HealthCheck}
  use Transformer

  @doc false
  @spec transform(Dsl.t()) :: {:ok, Dsl.t()} | {:error, DslError.t()}
  def transform(dsl_state) do
    with {:ok, listeners} <- get_unique_listeners(dsl_state),
         {:ok, routing_table} <- build_routing_table(dsl_state),
         {:ok, targets} <- build_unique_targets(dsl_state) do
      listeners = Macro.escape(listeners)
      routing_table = Macro.escape(routing_table)
      targets = Macro.escape(targets)

      dsl_state =
        dsl_state
        |> Transformer.eval(
          [listeners: listeners, routing_table: routing_table, targets: targets],
          quote do
            use Wayfarer.Server,
              listeners: unquote(listeners),
              targets: unquote(targets),
              routing_table: unquote(routing_table)
          end
        )

      {:ok, dsl_state}
    end
  end

  defp get_unique_listeners(dsl_state) do
    dsl_state
    |> Transformer.get_entities([:wayfarer])
    |> Enum.filter(&is_struct(&1, Config))
    |> Enum.flat_map(& &1.listeners.listeners)
    |> Enum.group_by(& &1.uri)
    |> Enum.reduce_while({:ok, []}, fn {uri, listeners_for_uri}, {:ok, all_listeners} ->
      listeners_for_uri
      |> Enum.uniq()
      |> case do
        [listener] ->
          {:cont, {:ok, [listener_to_options(listener) | all_listeners]}}

        _listeners ->
          {:halt,
           {:error,
            DslError.exception(
              module: Transformer.get_persisted(dsl_state, :module),
              path: [:wayfarer],
              message: "Multiple listeners for #{uri} with differing configurations."
            )}}
      end
    end)
  end

  defp build_routing_table(dsl_state) do
    table =
      dsl_state
      |> Transformer.get_entities([:wayfarer])
      |> Enum.filter(&is_struct(&1, Config))
      |> Enum.flat_map(fn config ->
        listeners = build_routing_listeners(config)
        host_patterns = build_routing_host_patterns(config)
        targets = build_routing_targets(config)

        for listener <- listeners, target <- targets do
          {listener, target, host_patterns, config.targets.algorithm}
        end
      end)

    {:ok, table}
  end

  defp build_routing_host_patterns(config) when is_struct(config, Config),
    do: build_routing_host_patterns(config.host_patterns.host_patterns)

  defp build_routing_host_patterns([]), do: ["*"]
  defp build_routing_host_patterns(patterns), do: Enum.map(patterns, & &1.pattern)

  defp build_routing_listeners(config) when is_struct(config, Config),
    do: build_routing_listeners(config.listeners.listeners)

  defp build_routing_listeners(listeners) do
    Enum.map(listeners, &{&1.scheme, IP.Address.to_tuple(&1.address), &1.port})
  end

  defp build_routing_targets(config) when is_struct(config, Config),
    do: build_routing_targets(config.targets.targets)

  defp build_routing_targets(targets) do
    Enum.map(targets, fn
      target when target.scheme == :plug ->
        {target.scheme, target.module}

      target ->
        {target.scheme, IP.Address.to_tuple(target.address), target.port}
    end)
  end

  defp build_targets(config) do
    with {:ok, global_checks} <- build_global_health_checks(config) do
      targets =
        config.targets.targets
        |> Enum.map(fn
          target when target.scheme == :plug ->
            target
            |> Map.from_struct()
            |> Map.drop([:address, :health_checks, :port, :uri])
            |> Enum.to_list()

          target when target.scheme in [:http, :https] ->
            health_checks =
              target.health_checks.health_checks
              |> Enum.map(&HealthCheck.to_options/1)
              |> Enum.concat(global_checks)
              |> Enum.uniq()
              |> maybe_add_default_health_check()

            target
            |> Map.from_struct()
            |> Map.drop([:module, :uri])
            |> Map.put(:health_checks, health_checks)
            |> Enum.to_list()
        end)

      {:ok, targets}
    end
  end

  defp maybe_add_default_health_check([]) do
    HealthCheck.default()
    |> HealthCheck.to_options()
    |> then(&[&1])
  end

  defp maybe_add_default_health_check(checks), do: checks

  defp build_unique_targets(dsl_state) do
    dsl_state
    |> Transformer.get_entities([:wayfarer])
    |> Enum.filter(&is_struct(&1, Config))
    |> Enum.reduce({:ok, []}, fn config, {:ok, targets} ->
      with {:ok, new_targets} <- build_targets(config) do
        {:ok, Enum.concat(targets, new_targets)}
      end
    end)
    |> case do
      {:ok, targets} -> {:ok, Enum.uniq(targets)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_global_health_checks(config) when is_list(config.health_checks.health_checks) do
    checks =
      config.health_checks.health_checks
      |> Enum.map(&HealthCheck.to_options/1)

    {:ok, checks}
  end

  defp build_global_health_checks(_), do: {:ok, []}

  defp listener_to_options(listener) do
    listener
    |> Map.from_struct()
    |> Map.delete(:uri)
    |> Enum.to_list()
  end
end
