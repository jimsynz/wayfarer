defmodule Wayfarer.Router do
  @moduledoc """
  Wayfarer's routing is implemented on top of an ETS table to allow for fast
  querying and easy mutation.

  This module provides a standardised interface to interact with a routing
  table.
  """
  import Wayfarer.Utils
  alias Wayfarer.Target.Selector
  require Selector

  @table_options [
    :duplicate_bag,
    :protected,
    :named_table,
    read_concurrency: true
  ]

  @type scheme :: :http | :https

  @typedoc """
  The row format for each route in the table.
  """
  @type route :: {listener, host_pattern, target, algorithm, health}

  @typedoc """
  Uniquely identifies a listener.
  """
  @type listener :: {scheme, :inet.ip_address(), :socket.port_number()}

  @typedoc """
  A fully qualified hostname optionally with a leading wildcard.
  """
  @type host_name :: String.t()

  @typedoc """
  Host patterns are built by splitting hostnames into segments and storing them
  as tuples.  Hosts with a leading wildcard (`*`) segment will have that segment
  replaced with a `:_`.

  ## Examples

  * `www.example.com` becomes `{"com", "example", "www"}`
  * `*.example.com` becomes `{"com", "example", :_}`
  """
  @type host_pattern :: tuple()

  @typedoc """
  Uniquely identifies a request target, either a remote http(s) server or a
  local `Plug`.
  """
  @type target ::
          {:http | :https | :ws | :wss, :inet.ip_address(), :socket.port_number(),
           :http1 | :http2 | :auto}
          | {:plug, module}
          | {:plug, {module, any}}

  @typedoc """
  Like `t:target/0` except that it can contain user input for the address portion.
  """
  @type target_input ::
          {:http | :https | :ws | :wss, Wayfarer.Utils.address_input(), :socket.port_number(),
           :http1 | :http2 | :auto}
          | {:plug, module}
          | {:plug, {module, any}}

  @typedoc """
  The algorithm used to select which target to forward requests to (when there
  is more than one matching target).
  """
  @type algorithm :: Selector.algorithm()

  @typedoc """
  The current health status of the target.
  """
  @type health :: :initial | :healthy | :unhealthy | :draining

  @doc """
  Create a new, empty routing table.

  This table is protected and owned by the calling process.
  """
  @spec init(module) :: {:ok, :ets.tid()} | {:error, any}
  def init(name) do
    {:ok, :ets.new(name, @table_options)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Add new route to the routing table.

  A route will be added for each host name with it's health state set to `:initial`.

  This should only ever be called by `Wayfarer.Server` directly.
  """
  @spec add_route(:ets.tid(), listener, target_input, [host_name], algorithm) ::
          :ok | {:error, any}
  def add_route(table, listener, target, host_names, algorithm) do
    with {:ok, entries} <- route_to_entries(table, listener, target, host_names, algorithm) do
      :ets.insert(table, entries)
      :ok
    end
  rescue
    e -> {:error, e}
  end

  @doc """
  Add a number of routes into the routing table.
  """
  @spec import_routes(:ets.tid(), [{listener, target_input, [host_name], algorithm}]) :: :ok
  def import_routes(table, routes) do
    with {:ok, entries} <- routes_to_entries(table, routes) do
      :ets.insert(table, entries)
      :ok
    end
  rescue
    e -> {:error, e}
  end

  @doc """
  Remove a listener from the routing table.

  This should only ever be done by `Wayfarer.Server` after it has finished
  draining connections.
  """
  @spec remove_listener(:ets.tid(), listener) :: :ok
  def remove_listener(table, listener) do
    :ets.match_delete(table, {listener, :_, :_, :_, :_})

    :ok
  rescue
    e -> {:error, e}
  end

  @doc """
  Remove a target from the routing table.

  This should only ever be done by `Wayfarer.Server` after it has finished
  draining connections.
  """
  @spec remove_target(:ets.tid(), target) :: :ok
  def remove_target(table, target) do
    :ets.match_delete(table, {:_, :_, target, :_, :_})

    :ok
  rescue
    e -> {:error, e}
  end

  @doc """
  Change a target's health state.
  """
  @spec update_target_health_status(:ets.tid(), target, health) :: :ok
  def update_target_health_status(table, {scheme, address, port, transport}, status) do
    # Match spec generated using:
    # :ets.fun2ms(fn {listener, host_pattern, {:http, {192, 168, 4, 26}, 80, transport}, algorithm, _} ->
    #   {listener, host_pattern, {:http, {192, 168, 4, 26}, 80, transport}, algorithm, :healthy}
    # end)

    match_spec = [
      {{:"$1", :"$2", {scheme, address, port, transport}, :"$3", :_}, [],
       [{{:"$1", :"$2", {{scheme, {address}, port, transport}}, :"$3", status}}]}
    ]

    :ets.select_replace(table, match_spec)

    :ok
  rescue
    e -> {:error, e}
  end

  @doc """
  Find healthy targets for a given listener and hostname.
  """
  @spec find_healthy_targets(:ets.tid(), listener, String.t()) ::
          {:ok, [{target, algorithm}]} | {:error, any}
  def find_healthy_targets(table, listener, hostname) do
    # Match spec generated with:
    # :ets.fun2ms(fn {:listener, {segment, "example", "com"}, target, algorithm, :healthy}
    #                when segment == "www" or segment == :_ ->
    #   {target, algorithm}
    # end)

    [head | tail] =
      hostname
      |> String.trim_trailing(".")
      |> String.split(".")

    host_match = [:"$1" | tail] |> List.to_tuple()

    match_spec =
      [
        {{listener, host_match, :"$2", :"$3", :healthy},
         [{:orelse, {:==, :"$1", head}, {:==, :"$1", :_}}], [{{:"$2", :"$3"}}]}
      ]

    targets =
      table
      |> :ets.select(match_spec)
      |> Enum.uniq()

    {:ok, targets}
  rescue
    e -> {:error, e}
  end

  defp routes_to_entries(table, routes) do
    Enum.reduce_while(routes, {:ok, []}, fn {listener, target, host_names, algorithm},
                                            {:ok, entries} ->
      case route_to_entries(table, listener, target, host_names, algorithm) do
        {:ok, new_entries} -> {:cont, {:ok, Enum.concat(entries, new_entries)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp route_to_entries(table, listener, target, host_names, algorithm)
       when Selector.is_algorithm(algorithm) do
    with {:ok, listener} <- sanitise_listener(listener),
         {:ok, target} <- sanitise_target(target),
         {:ok, patterns} <- host_names_to_pattern(host_names),
         health_state <- current_health_state(table, target) do
      entries = Enum.map(patterns, &{listener, &1, target, algorithm, health_state})
      {:ok, entries}
    end
  end

  defp route_to_entries(_table, _listener, _target, _host_names, algorithm),
    do:
      {:error,
       ArgumentError.exception(
         message: "Value `#{inspect(algorithm)}` is not a valid load balancing algorithm."
       )}

  defp current_health_state(table, {scheme, address, port, transport}) do
    # Generated using
    # :ets.fun2ms(fn {_, _, :target, :_, health} -> health end)

    match_spec = [
      {{:_, :_, {scheme, address, port, transport}, :_, :"$1"}, [], [:"$1"]}
    ]

    case :ets.select(table, match_spec, 1) do
      {[health], _} -> health
      _ -> :initial
    end
  end

  defp host_names_to_pattern(host_names) do
    Enum.reduce_while(host_names, {:ok, []}, fn host_name, {:ok, patterns} ->
      case host_name_to_pattern(host_name) do
        {:ok, pattern} -> {:cont, {:ok, [pattern | patterns]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp host_name_to_pattern(host_name) when is_binary(host_name) do
    pattern =
      host_name
      |> String.trim_trailing(".")
      |> String.split(".")
      |> Enum.reduce({}, fn
        "*", {} -> {:_}
        segment, pattern -> Tuple.append(pattern, segment)
      end)

    {:ok, pattern}
  end

  defp host_name_to_pattern(host_name) do
    {:error,
     ArgumentError.exception(
       message: "Value `#{inspect(host_name)}` is not a valid host expression."
     )}
  end

  defp sanitise_listener({scheme, address, port}) do
    with {:ok, scheme} <- sanitise_scheme(scheme),
         {:ok, address} <- sanitise_ip_address(address),
         {:ok, port} <- sanitise_port(port) do
      {:ok, {scheme, address, port}}
    end
  end

  defp sanitise_listener(listener),
    do: {:error, ArgumentError.exception(message: "Not a valid listener: `#{inspect(listener)}")}

  defp sanitise_transport(transport) when transport in [:http1, :http2, :auto],
    do: {:ok, transport}

  defp sanitise_transport(transport),
    do:
      {:error,
       ArgumentError.exception(message: "Not a valid target transport: `#{inspect(transport)}`")}

  defp sanitise_target({:plug, module}), do: sanitise_target({:plug, module, []})

  defp sanitise_target({:plug, module, _}) do
    if Spark.implements_behaviour?(module, Plug) do
      {:ok, {:plug, module}}
    else
      {:error,
       ArgumentError.exception(
         message: "Module `#{inspect(module)}` does not implement the `Plug` behaviour."
       )}
    end
  end

  defp sanitise_target({scheme, address, port, transport}) do
    with {:ok, scheme} <- sanitise_scheme(scheme),
         {:ok, address} <- sanitise_ip_address(address),
         {:ok, port} <- sanitise_port(port),
         {:ok, transport} <- sanitise_transport(transport) do
      {:ok, {scheme, address, port, transport}}
    end
  end

  defp sanitise_target(target),
    do: {:error, ArgumentError.exception(message: "Not a valid target: `#{inspect(target)}")}
end
