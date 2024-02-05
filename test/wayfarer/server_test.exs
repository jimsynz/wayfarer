defmodule Wayfarer.ServerTest do
  @moduledoc false
  use ExUnit.Case, async: false
  use Support.PortTracker
  use Support.HttpRequest
  alias Support.HttpRequest
  alias Support.HttpServer
  alias Support.Utils
  alias Wayfarer.{Listener, Server, Target}
  import IP.Sigil

  setup do
    start_supervised!(Listener.Supervisor)
    start_supervised!(Target.Supervisor)
    start_supervised!(Server.Supervisor)

    :ok
  end

  describe "init/1" do
    test "it requires a module option which implements the `Wayfarer.Server` behaviour" do
      assert {:stop, reason} = Server.init(module: URI)
      assert reason =~ ~r/does not implement/
    end

    test "a list of listeners can be passed as options and they are started" do
      port = random_port()

      assert {:ok, _state} =
               Server.init(
                 module: Support.Example,
                 listeners: [[address: ~i"127.0.0.1", port: port, scheme: :http]]
               )

      assert {:ok, %{status: 502}} = request(:http, ~i"127.0.0.1", port)
    end

    test "a list of targets can be passed as options and they are started" do
      port = random_port()

      assert {:ok, _state} =
               Server.init(
                 module: Support.Example,
                 targets: [[address: ~i"127.0.0.1", port: port, scheme: :http]]
               )

      assert {:ok, :initial} =
               Target.current_status({Support.Example, :http, ~i"127.0.0.1", port})
    end

    test "an initial routing table can be passed as options" do
      listen_port = random_port()
      target_port = random_port()

      assert {:ok, _state} =
               Server.init(
                 module: Support.Example,
                 routing_table: [
                   {
                     {:http, ~i"127.0.0.1", listen_port},
                     {:http, ~i"127.0.0.1", target_port},
                     ["example.com"],
                     :round_robin
                   }
                 ]
               )

      assert :ets.tab2list(Support.Example) == [
               {{:http, {127, 0, 0, 1}, listen_port}, {"example", "com"},
                {:http, {127, 0, 0, 1}, target_port}, :round_robin, :initial}
             ]
    end
  end

  describe "add_target/2" do
    test "it can add a new target to the server" do
      {:ok, pid} = Server.start_link(module: Support.Example)

      target_port = random_port()

      {:ok, _} = HttpServer.start_link(target_port, 200, "OK")

      assert :ok =
               Server.add_target(pid,
                 address: ~i"127.0.0.1",
                 port: target_port,
                 scheme: :http,
                 health_checks: [[interval: 10, threshold: 3]]
               )
    end
  end

  describe "drain_target/2" do
    test "it stops new requests being forwarded to the target" do
      listener_port = random_port()
      target_port = random_port()

      {:ok, _} = HttpServer.start_link(target_port, 200, "OK")

      {:ok, pid} =
        Server.start_link(
          module: Support.Example,
          listeners: [
            [
              scheme: :http,
              address: ~i"127.0.0.1",
              port: listener_port
            ]
          ],
          targets: [
            [
              scheme: :http,
              address: ~i"127.0.0.1",
              port: target_port,
              health_checks: [[interval: 10, threshold: 3]]
            ]
          ],
          routing_table: [
            {{:http, ~i"127.0.0.1", listener_port}, {:http, ~i"127.0.0.1", target_port},
             ["example.com"], :round_robin}
          ]
        )

      Utils.wait_for_target_state({Support.Example, :http, ~i"127.0.0.1", target_port}, :healthy)

      assert {:ok, %{status: 200}} = HttpRequest.request(:http, ~i"127.0.0.1", listener_port)

      assert :ok = Server.drain_target(pid, {:http, ~i"127.0.0.1", target_port})
    end
  end
end
