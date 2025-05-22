defmodule Wayfarer.Utils do
  @moduledoc """
  A grab-bag of useful functions which are used all over the codebase.
  """

  @type address_input :: IP.Address.t() | String.t() | :inet.ip_address()
  @type port_number :: 1..0xFFFF
  @type scheme :: :http | :https | :ws | :wss
  @type transport :: :http1 | :http2 | :auto

  @doc """
  Verify an IP address and convert it into a tuple.
  """
  @spec sanitise_ip_address(address_input) :: {:ok, :inet.ip_address()} | {:error, any}
  def sanitise_ip_address(address) when is_binary(address) do
    with {:ok, address} <- IP.Address.from_string(address) do
      {:ok, IP.Address.to_tuple(address)}
    end
  end

  def sanitise_ip_address(address) when is_struct(address, IP.Address),
    do: {:ok, IP.Address.to_tuple(address)}

  def sanitise_ip_address(address) when is_tuple(address) do
    with {:ok, _} <- IP.Address.from_tuple(address) do
      {:ok, address}
    end
  end

  def sanitise_ip_address(address),
    do:
      {:error,
       ArgumentError.exception(message: "Value `#{inspect(address)}` is not a valid IP address.")}

  @doc """
  Verify a port number.
  """
  @spec sanitise_port(port_number) :: {:ok, port_number} | {:error, any}
  def sanitise_port(port) when is_integer(port) and port > 0 and port <= 0xFFFF, do: {:ok, port}

  def sanitise_port(port),
    do:
      {:error,
       ArgumentError.exception(message: "Value `#{inspect(port)}` is not a valid port number.")}

  @doc """
  Verify a scheme.
  """
  @spec sanitise_scheme(scheme) :: {:ok, scheme} | {:error, any}
  def sanitise_scheme(scheme) when scheme in [:http, :https, :ws, :wss], do: {:ok, scheme}

  def sanitise_scheme(scheme),
    do:
      {:error,
       ArgumentError.exception(
         message: "Value `#{inspect(scheme)}` is not a supported URI scheme."
       )}

  @doc """
  Convert a scheme, address, port tuple into a `URI`.
  """
  @spec to_uri(scheme, address_input, port_number) :: {:ok, URI.t()} | {:error, any}
  def to_uri(scheme, address, port) do
    with {:ok, scheme} <- sanitise_scheme(scheme),
         {:ok, address} <- sanitise_ip_address(address),
         {:ok, address} <- IP.Address.from_tuple(address),
         {:ok, port} <- sanitise_port(port),
         {:ok, uri} <- URI.new("") do
      {:ok,
       Map.merge(uri, %{
         scheme: to_string(scheme),
         host: to_string(address),
         port: port
       })}
    end
  end

  @doc """
  Convert a list of targets into a match spec guard.
  """
  @spec targets_to_ms_guard(atom, [{scheme, :inet.ip_address(), port_number, transport}]) :: [
          {atom, any, any}
        ]
  def targets_to_ms_guard(_var, []), do: []

  def targets_to_ms_guard(var, [head | tail]),
    do: targets_to_ms_guard(var, tail, {:"=:=", var, target_to_ms(head)})

  defp targets_to_ms_guard(_var, [], guard), do: [guard]

  defp targets_to_ms_guard(var, [head | tail], guard),
    do: targets_to_ms_guard(var, tail, {:orelse, {:"=:=", var, target_to_ms(head)}, guard})

  @doc """
  Convert a target tuple into a tuple safe for injection into a match spec.
  """
  @spec target_to_ms({scheme, :inet.ip_address(), port_number, transport}) ::
          {{scheme, {:inet.ip_address()}, port_number, transport}}
  def target_to_ms({scheme, address, port, transport}) when is_tuple(address),
    do: {{scheme, {address}, port, transport}}
end
