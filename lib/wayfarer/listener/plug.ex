defmodule Wayfarer.Listener.Plug do
  @moduledoc """
  Plug pipeline to handle inbound HTTP connections.
  """
  import Plug.Conn
  @behaviour Plug

  @doc false
  @impl true
  def init(options) do
    options
  end

  @doc false
  @impl true
  def call(conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(502, "Bad Gateway")
  end
end
