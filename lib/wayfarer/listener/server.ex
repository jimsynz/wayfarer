defmodule Wayfarer.Listener.Server do
  @moduledoc """
  A GenServer which manages the state of each listener.
  """

  alias Wayfarer.Listener.Plug
  alias Wayfarer.Listener.Registry, as: ListenerRegistry

  use GenServer, restart: :transient
  require Logger

  # How long to wait for connections to drain when shutting down a listener.
  @drain_timeout :timer.seconds(60)

  @type options :: [
          scheme: :http | :https,
          port: :inet.port_number(),
          ip: :inet.socket_address(),
          keyfile: binary(),
          certfile: binary(),
          otp_app: binary() | atom(),
          cipher_suite: :strong | :compatible,
          display_plug: module(),
          startup_log: Logger.level() | false,
          thousand_island_options: ThousandIsland.options(),
          http_1_options: Bandit.http_1_options(),
          http_2_options: Bandit.http_2_options(),
          websocket_options: Bandit.websocket_options()
        ]

  @doc false
  @spec start_link(options) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @doc false
  @impl true
  def init(options) do
    options =
      options
      |> Keyword.put(:plug, Plug)
      |> Keyword.put(:startup_log, false)
      |> Keyword.update(
        :thousand_island_options,
        [shutdown_timeout: @drain_timeout],
        &Keyword.put_new(&1, :shutdown_timeout, @drain_timeout)
      )

    with {:ok, scheme} <- fetch_required_option(options, :scheme),
         {:ok, pid} <- Bandit.start_link(options),
         {:ok, %{address: addr, port: port}} <- ThousandIsland.listener_info(pid),
         {:ok, _pid} <- Registry.register(ListenerRegistry, {scheme, addr, port}, pid) do
      listen_url = listen_url(scheme, addr, port)
      version = Application.spec(:wayfarer)[:vsn]
      Logger.info("Started Wayfarer v#{version} listener on #{listen_url}")

      {:ok, %{server: pid, options: options, addr: addr}}
    end
  end

  @doc false
  @impl true
  def terminate(:normal, %{server: server}) do
    GenServer.stop(server, :normal)
  end

  defp fetch_required_option(options, option) do
    case Keyword.fetch(options, option) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:required_option, option}}
    end
  end

  defp listen_url(scheme, {:local, socket_path}, _), do: "#{scheme}:#{socket_path}"

  defp listen_url(scheme, address, port) when tuple_size(address) == 4 do
    "#{scheme}://#{:inet.ntoa(address)}:#{port}"
    |> URI.new!()
    |> to_string()
  end

  defp listen_url(scheme, address, port) when tuple_size(address) == 8 do
    "#{scheme}://[#{:inet.ntoa(address)}]:#{port}"
    |> URI.new!()
    |> to_string()
  end
end
