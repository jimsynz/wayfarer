defmodule Wayfarer.ListenerTest do
  @moduledoc false
  use ExUnit.Case, async: false
  use Support.PortTracker
  use Support.HttpRequest
  use Mimic

  alias Wayfarer.{Listener, Router}
  import IP.Sigil

  setup do
    start_supervised!(Wayfarer.Listener.Supervisor)
    {:ok, _table} = Router.init(Support.Example)

    :ok
  end

  test "it can start an HTTP listener" do
    port = random_port()

    assert {:ok, _pid} =
             Listener.start_link(
               scheme: :http,
               address: ~i"127.0.0.1",
               port: port,
               module: Support.Example
             )

    assert {:ok, %{status: 502}} = request(:http, ~i"127.0.0.1", port)
  end

  test "it can start an HTTPS listener" do
    port = random_port()

    certfile = Path.join(__DIR__, "../support/test.cert")
    keyfile = Path.join(__DIR__, "../support/test.key")

    assert {:ok, _pid} =
             Listener.start_link(
               scheme: :https,
               address: ~i"127.0.0.1",
               port: port,
               certfile: certfile,
               keyfile: keyfile,
               module: Support.Example,
               cipher_suite: :compatible
             )

    assert {:ok, %{status: 502}} =
             request(:https, ~i"127.0.0.1", port,
               host: "www.example.com",
               options: [transport_opts: [verify: :verify_none]]
             )
  end

  describe "handle_call(:terminate, _, _)" do
    setup :set_mimic_global

    test "it cleanly shuts down" do
      port = random_port()

      assert {:ok, pid} =
               Listener.start_link(
                 scheme: :http,
                 address: ~i"127.0.0.1",
                 port: port,
                 module: Support.Example
               )

      assert {:ok, :draining} = GenServer.call(pid, :terminate)
      refute Process.alive?(pid)
    end

    test "it correctly drains connections" do
      port = random_port()

      assert {:ok, pid} =
               Listener.start_link(
                 scheme: :http,
                 address: ~i"127.0.0.1",
                 port: port,
                 module: Support.Example,
                 drain_timeout: 123_456
               )

      ThousandIsland
      |> expect(:stop, fn _pid, timeout ->
        assert timeout == 123_456
      end)

      assert {:ok, :draining} = GenServer.call(pid, :terminate)
    end
  end
end
