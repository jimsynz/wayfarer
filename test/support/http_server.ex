defmodule Support.HttpServer do
  @moduledoc """
  A basic HTTP server which returns a canned response.
  """

  @behaviour Plug
  import Plug.Conn

  @doc false
  @spec start_link(:inet.port_number(), 100..599, String.t()) :: Supervisor.on_start()
  def start_link(port, status, body, notify \\ false) do
    notify =
      case notify do
        true -> self()
        pid when is_pid(pid) -> pid
        _ -> false
      end

    Bandit.start_link(
      scheme: :http,
      port: port,
      ip: {127, 0, 0, 1},
      plug: {__MODULE__, {status, body, notify}}
    )
  end

  @doc false
  @impl true
  @spec init(any) :: any
  def init({status, body, notify}), do: {status, body, notify}

  @doc false
  @impl true
  @spec call(Plug.Conn.t(), any) :: Plug.Conn.t()
  def call(conn, {status, body, notify}) do
    if is_pid(notify) do
      Process.send_after(notify, {:request, __MODULE__, conn}, 20)
    end

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, body)
  end

  @doc "Wait for the next HTTP request to be served"
  @spec await_request :: Plug.Conn.t()
  def await_request do
    receive do
      {:request, __MODULE__, conn} -> conn
    end
  end

  @doc "Wait for a certain number of requests to have been served"
  @spec await_requests(non_neg_integer()) :: [Plug.Conn.t()]
  def await_requests(how_many \\ 1) when how_many > 0 and is_integer(how_many) do
    Enum.map(1..how_many, fn _ ->
      await_request()
    end)
  end
end
