defmodule Wayfarer.Target.Table do
  @moduledoc """
  Manages an ETS table containing target statuses.
  """
  use GenServer
  alias Wayfarer.Target.Server

  @doc false
  @spec start_link(any) :: GenServer.on_start()
  def start_link(args), do: GenServer.start_link(__MODULE__, args)

  @doc false
  @spec init(any) :: {:ok, :ets.tid(), :hibernate}
  def init(_) do
    table =
      __MODULE__
      |> :ets.new([:set, :public, :named_table])

    {:ok, table, :hibernate}
  end

  @doc """
  Store the target status in the table.
  """
  @spec set_status(:http | :https, :inet.ip_address(), :inet.port_number(), Server.status()) ::
          :ok
  def set_status(scheme, ip, port, status) do
    :ets.insert(__MODULE__, {{scheme, ip, port}, status})
    :ok
  end

  @doc """
  Return the status of a target
  """
  @spec get_status(:http | :https, :inet.ip_address(), :inet.port_number()) ::
          {:ok, Server.status()} | :error
  def get_status(scheme, ip, port) do
    case :ets.lookup_element(__MODULE__, {scheme, ip, port}, 2, nil) do
      nil -> :error
      status -> {:ok, status}
    end
  end

  @doc """
  Return all the target statuses
  """
  @spec status :: %{{:http | :https, :inet.ip_address(), :inet.port_number()} => Server.status()}
  def status do
    __MODULE__
    |> :ets.tab2list()
    |> Map.new()
  end
end
