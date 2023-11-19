defmodule Wayfarer.ServerTest do
  @moduledoc false
  use ExUnit.Case, async: false
  use Support.PortTracker
  use Support.HttpRequest
  import IP.Sigil

  setup do
    start_supervised!(Wayfarer.Listener.Supervisor)
    start_supervised!(Wayfarer.Target.Supervisor)
    start_supervised!(Wayfarer.Server.Supervisor)

    :ok
  end

  describe "init/1" do
    test "it requires a module option which implements the `Wayfarer.Server` behaviour" do
      assert {:stop, reason} = Wayfarer.Server.init(module: URI)
      assert reason =~ ~r/does not implement/
    end

    test "a list of listeners can be passed as options and they are started" do
      port = random_port()

      assert {:ok, _state} =
               Wayfarer.Server.init(
                 module: Support.Example,
                 listeners: [[address: ~i"127.0.0.1", port: port, scheme: :http]]
               )

      assert {:ok, %{status: 502}} = request(:http, ~i"127.0.0.1", port)
    end

    test "a list of targets can be passed as options and they are started" do
      port = random_port()

      assert {:ok, _state} =
               Wayfarer.Server.init(
                 module: Support.Example,
                 targets: [[address: ~i"127.0.0.1", port: port, scheme: :http]]
               )

      assert {:ok, :initial} =
               Wayfarer.Target.current_status({Support.Example, :http, ~i"127.0.0.1", port})
    end

    test "an initial routing table can be passed as options" do
      listen_port = random_port()
      target_port = random_port()

      assert {:ok, _state} =
               Wayfarer.Server.init(
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
end
