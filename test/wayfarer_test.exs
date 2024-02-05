defmodule WayfarerTest do
  @moduledoc false
  use ExUnit.Case, async: false
  doctest Wayfarer

  alias Support.HttpServer
  alias Wayfarer.Target.TotalConnections

  use Support.HttpRequest
  use Support.PortTracker
  use Support.Utils

  import IP.Sigil

  setup do
    start_supervised!(Wayfarer.Target.Supervisor)
    start_supervised!(Wayfarer.Listener.Supervisor)
    start_supervised!(Wayfarer.Server.Supervisor)

    :ok
  end

  defmodule IntegrationProxy do
    @moduledoc false
    use Wayfarer.Server
  end

  describe "integration tests" do
    test "round robin integration test" do
      listener_port = random_port()
      target0_port = random_port()
      target1_port = random_port()

      {:ok, _} = HttpServer.start_link(target0_port, 200, "OK", true)
      {:ok, _} = HttpServer.start_link(target1_port, 200, "OK", true)

      {:ok, _proxy} =
        IntegrationProxy.start_link(
          listeners: [[scheme: :http, address: ~i"127.0.0.1", port: listener_port]],
          targets: [
            [
              scheme: :http,
              address: ~i"127.0.0.1",
              port: target0_port,
              health_checks: [[interval: 100]]
            ],
            [
              scheme: :http,
              address: ~i"127.0.0.1",
              port: target1_port,
              health_checks: [[interval: 100]]
            ]
          ],
          routing_table: [
            {{:http, ~i"127.0.0.1", listener_port}, {:http, ~i"127.0.0.1", target0_port},
             ["www.example.com"], :round_robin},
            {{:http, ~i"127.0.0.1", listener_port}, {:http, ~i"127.0.0.1", target1_port},
             ["www.example.com"], :round_robin}
          ]
        )

      wait_for_target_state({IntegrationProxy, :http, ~i"127.0.0.1", target0_port}, :healthy)
      wait_for_target_state({IntegrationProxy, :http, ~i"127.0.0.1", target1_port}, :healthy)

      assert {:ok, %{status: 200}} =
               request(:http, ~i"127.0.0.1", listener_port, host: "www.example.com")

      assert {:ok, %{status: 200}} =
               request(:http, ~i"127.0.0.1", listener_port, host: "www.example.com")

      assert [1, 1] =
               [
                 {:http, {127, 0, 0, 1}, target0_port},
                 {:http, {127, 0, 0, 1}, target1_port}
               ]
               |> TotalConnections.proxy_count()
               |> Enum.map(&elem(&1, 1))

      for _ <- 1..10 do
        assert {:ok, %{status: 200}} =
                 request(:http, ~i"127.0.0.1", listener_port, host: "www.example.com")

        assert {:ok, %{status: 200}} =
                 request(:http, ~i"127.0.0.1", listener_port, host: "www.example.com")
      end

      assert [11, 11] =
               [
                 {:http, {127, 0, 0, 1}, target0_port},
                 {:http, {127, 0, 0, 1}, target1_port}
               ]
               |> TotalConnections.proxy_count()
               |> Enum.map(&elem(&1, 1))
    end
  end
end
