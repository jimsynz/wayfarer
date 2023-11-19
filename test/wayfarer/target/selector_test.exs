defmodule Wayfarer.Target.SelectorTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use Plug.Test
  use Mimic
  use Support.PortTracker
  alias Wayfarer.Target.{ActiveConnections, Selector, TotalConnections}

  @algorithms ~w[least_connections random round_robin sticky]a

  describe "choose/3" do
    test "when there are no targets to choose from it returns an error regardless of algorithm" do
      conn = conn(:get, "/")

      for algorithm <- @algorithms do
        assert :error = Selector.choose(conn, [], algorithm)
      end
    end

    test "when there is only one target to choose it is used regardless of algorithm" do
      conn = conn(:get, "/")
      target = {:http, {127, 0, 0, 1}, random_port()}

      for algorithm <- @algorithms do
        assert {:ok, ^target} = Selector.choose(conn, [target], algorithm)
      end
    end

    test "sticky targets route repeated requests from the same client to the same target" do
      paths = ["/", "/sign-in", "/dashboard"]

      target0 = {:http, {127, 0, 0, 1}, random_port()}
      target1 = {:http, {127, 0, 0, 1}, random_port()}

      wayfarer = %{
        listener: %{
          address: {127, 0, 0, 1},
          port: random_port(),
          remote_ip: {192, 0, 2, 1}
        }
      }

      peer_data = %{address: {192, 0, 2, 2}, port: random_port(), ssl_cert: nil}

      assert {:http, {127, 0, 0, 1}, _} =
               paths
               |> Enum.reduce(nil, fn path, last_target ->
                 conn =
                   conn(:get, path)
                   |> put_private(:wayfarer, wayfarer)
                   |> put_peer_data(peer_data)

                 assert {:ok, target} = Selector.choose(conn, [target0, target1], :sticky)

                 if is_nil(last_target) do
                   target
                 else
                   assert target == last_target
                   last_target
                 end
               end)
    end

    test "random targets route requests to random targets" do
      paths = ["/", "/sign-in", "/dashboard"]

      target0 = {:http, {127, 0, 0, 1}, random_port()}
      target1 = {:http, {127, 0, 0, 1}, random_port()}

      for path <- paths do
        conn = conn(:get, path)

        assert {:ok, target} = Selector.choose(conn, [target0, target1], :random)
        assert target in [target0, target1]
      end
    end

    test "least_connections targets route requests to the target with the least connections" do
      paths = ["/", "/sign-in", "/dashboard"]

      target0 = {:http, {127, 0, 0, 1}, random_port()}
      target1 = {:http, {127, 0, 0, 1}, random_port()}

      ActiveConnections
      |> stub(:request_count, fn _targets ->
        %{target0 => 37, target1 => 3}
      end)

      for path <- paths do
        conn = conn(:get, path)

        assert {:ok, ^target1} = Selector.choose(conn, [target0, target1], :least_connections)
      end
    end

    test "round_robin targets route requests to the target with lowest total connections" do
      paths = ["/", "/sign-in", "/dashboard"]

      target0 = {:http, {127, 0, 0, 1}, random_port()}
      target1 = {:http, {127, 0, 0, 1}, random_port()}

      TotalConnections
      |> stub(:proxy_count, fn _targets ->
        %{target0 => 37, target1 => 3}
      end)

      for path <- paths do
        conn = conn(:get, path)

        assert {:ok, ^target1} = Selector.choose(conn, [target0, target1], :round_robin)
      end
    end
  end
end
