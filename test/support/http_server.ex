defmodule Support.HttpServer do
  @moduledoc """
  A basic HTTP server which returns a canned response.
  """

  @behaviour Plug
  import Plug.Conn

  @doc false
  @spec start_link(:inet.port_number(), 100..599, String.t()) :: Supervisor.on_start()
  def start_link(port, status, body),
    do:
      Bandit.start_link(
        scheme: :http,
        port: port,
        ip: {127, 0, 0, 1},
        plug: {__MODULE__, {status, body}}
      )

  @doc false
  @impl true
  @spec init(any) :: any
  def init({status, body}), do: {status, body}

  @doc false
  @impl true
  @spec call(Plug.Conn.t(), any) :: Plug.Conn.t()
  def call(conn, {status, body}) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, body)
  end
end
