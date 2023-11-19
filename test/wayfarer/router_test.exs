defmodule Wayfarer.RouterTest do
  @moduledoc false
  use ExUnit.Case, async: false
  use Support.PortTracker
  alias Wayfarer.Router
  import IP.Sigil

  describe "init/1" do
    test "it creates a new ETS table" do
      assert {:ok, table} = Router.init(Support.Example)

      assert [] = :ets.tab2list(table)
    end
  end

  describe "add_route/5" do
    test "when the listener is not valid it returns an error" do
      {:ok, table} = Router.init(Support.Example)

      assert {:error, error} =
               Router.add_route(
                 table,
                 :wat,
                 {:http, ~i"127.0.0.1", random_port()},
                 ["example.com"],
                 :round_robin
               )

      assert Exception.message(error) =~ ~r/not a valid listener/i
    end

    test "when the target is not valid it returns an error" do
      {:ok, table} = Router.init(Support.Example)

      assert {:error, error} =
               Router.add_route(
                 table,
                 {:http, ~i"127.0.0.1", random_port()},
                 :wat,
                 ["example.com"],
                 :round_robin
               )

      assert Exception.message(error) =~ ~r/not a valid target/i
    end

    test "it converts wildcard hostnames into tuples" do
      {:ok, table} = Router.init(Support.Example)

      listener = {:http, {127, 0, 0, 1}, random_port()}
      target = {:http, {127, 0, 0, 1}, random_port()}

      assert :ok = Router.add_route(table, listener, target, ["*.example.com"], :round_robin)

      assert :ets.tab2list(table) == [
               {listener, {:_, "example", "com"}, target, :round_robin, :initial}
             ]
    end

    test "it converts normal hostnames into tuples" do
      {:ok, table} = Router.init(Support.Example)

      listener = {:http, {127, 0, 0, 1}, random_port()}
      target = {:http, {127, 0, 0, 1}, random_port()}

      assert :ok = Router.add_route(table, listener, target, ["www.example.com"], :round_robin)

      assert :ets.tab2list(table) == [
               {listener, {"www", "example", "com"}, target, :round_robin, :initial}
             ]
    end

    test "it converts multiple hostnames into multiple routes" do
      {:ok, table} = Router.init(Support.Example)

      listener = {:http, {127, 0, 0, 1}, random_port()}
      target = {:http, {127, 0, 0, 1}, random_port()}

      assert :ok =
               Router.add_route(
                 table,
                 listener,
                 target,
                 ["example.com", "*.example.com"],
                 :round_robin
               )

      all_routes =
        table
        |> :ets.tab2list()
        |> Enum.sort()

      assert all_routes == [
               {listener, {"example", "com"}, target, :round_robin, :initial},
               {listener, {:_, "example", "com"}, target, :round_robin, :initial}
             ]
    end

    test "when not a valid algorithm it returns an error" do
      {:ok, table} = Router.init(Support.Example)

      listener = {:http, {127, 0, 0, 1}, random_port()}
      target = {:http, {127, 0, 0, 1}, random_port()}

      assert {:error, error} =
               Router.add_route(table, listener, target, ["www.example.com"], :marty)

      assert Exception.message(error) =~ ~r/not a valid load balancing algorithm/i
    end
  end

  describe "import_routes/2" do
    test "it inserts multiple routes into the routing table" do
      {:ok, table} = Router.init(Support.Example)

      listener0 = {:http, {127, 0, 0, 1}, random_port()}
      target0 = {:http, {127, 0, 0, 1}, random_port()}
      listener1 = {:http, {127, 0, 0, 1}, random_port()}
      target1 = {:http, {127, 0, 0, 1}, random_port()}

      assert :ok =
               Router.import_routes(table, [
                 {listener0, target0, ["0.example.com"], :round_robin},
                 {listener1, target1, ["1.example.com"], :random}
               ])

      all_routes =
        table
        |> :ets.tab2list()
        |> Enum.sort()

      assert all_routes ==
               Enum.sort([
                 {listener0, {"0", "example", "com"}, target0, :round_robin, :initial},
                 {listener1, {"1", "example", "com"}, target1, :random, :initial}
               ])
    end
  end

  describe "remove_listener/2" do
    test "removes any matching routes from the table" do
      {:ok, table} = Router.init(Support.Example)

      listener0 = {:http, {127, 0, 0, 1}, random_port()}
      target0 = {:http, {127, 0, 0, 1}, random_port()}
      listener1 = {:http, {127, 0, 0, 1}, random_port()}
      target1 = {:http, {127, 0, 0, 1}, random_port()}

      Router.import_routes(table, [
        {listener0, target0, ["0.example.com"], :round_robin},
        {listener1, target1, ["1.example.com"], :random}
      ])

      Router.remove_listener(table, listener0)

      assert :ets.tab2list(table) == [
               {listener1, {"1", "example", "com"}, target1, :random, :initial}
             ]
    end
  end

  describe "remove_target/2" do
    test "removes any matching routes from the table" do
      {:ok, table} = Router.init(Support.Example)

      listener0 = {:http, {127, 0, 0, 1}, random_port()}
      target0 = {:http, {127, 0, 0, 1}, random_port()}
      listener1 = {:http, {127, 0, 0, 1}, random_port()}
      target1 = {:http, {127, 0, 0, 1}, random_port()}

      Router.import_routes(table, [
        {listener0, target0, ["0.example.com"], :round_robin},
        {listener1, target1, ["1.example.com"], :random}
      ])

      Router.remove_target(table, target0)

      assert :ets.tab2list(table) == [
               {listener1, {"1", "example", "com"}, target1, :random, :initial}
             ]
    end
  end

  describe "update_target_health_status/3" do
    test "updates all routes to the specified target with the new health status" do
      {:ok, table} = Router.init(Support.Example)

      listener0 = {:http, {127, 0, 0, 1}, random_port()}
      target0 = {:http, {127, 0, 0, 1}, random_port()}
      listener1 = {:http, {127, 0, 0, 1}, random_port()}
      target1 = {:http, {127, 0, 0, 1}, random_port()}

      Router.import_routes(table, [
        {listener0, target0, ["0.example.com"], :round_robin},
        {listener1, target1, ["1.example.com"], :random}
      ])

      assert :ok = Router.update_target_health_status(table, target1, :healthy)

      all_routes =
        table
        |> :ets.tab2list()
        |> Enum.sort()

      assert all_routes ==
               Enum.sort([
                 {listener0, {"0", "example", "com"}, target0, :round_robin, :initial},
                 {listener1, {"1", "example", "com"}, target1, :random, :healthy}
               ])
    end
  end

  describe "find_healthy_targets/3" do
    setup do
      {:ok, table} = Router.init(Support.Example)

      listener = {:http, {127, 0, 0, 1}, random_port()}
      target0 = {:http, {127, 0, 0, 1}, random_port()}
      target1 = {:http, {127, 0, 0, 1}, random_port()}

      :ok =
        Router.import_routes(table, [
          {listener, target0, ["*.example.com"], :random},
          {listener, target1, ["example.com"], :random}
        ])

      :ok = Router.update_target_health_status(table, target0, :healthy)
      :ok = Router.update_target_health_status(table, target1, :healthy)

      {:ok, table: table, listener: listener, target0: target0, target1: target1}
    end

    test "when the request matches a wildcard route it returns the target", %{
      table: table,
      listener: listener,
      target0: target0
    } do
      assert {:ok, [{^target0, :random}]} =
               Router.find_healthy_targets(table, listener, "www.example.com")
    end

    test "when the request matches a specific route it returns the target", %{
      table: table,
      listener: listener,
      target1: target1
    } do
      assert {:ok, [{^target1, :random}]} =
               Router.find_healthy_targets(table, listener, "example.com")
    end

    test "when the request matches a multiple targets it returns them both", %{
      table: table,
      listener: listener,
      target0: target0,
      target1: target1
    } do
      :ok =
        Router.import_routes(table, [
          {listener, target1, ["www.example.com"], :random}
        ])

      assert {:ok, targets} = Router.find_healthy_targets(table, listener, "www.example.com")
      assert Enum.sort(targets) == Enum.sort([{target0, :random}, {target1, :random}])
    end

    test "when the request matches the same target multiple times it returns it once", %{
      table: table,
      listener: listener,
      target0: target0
    } do
      :ok =
        Router.import_routes(table, [
          {listener, target0, ["www.example.com"], :random}
        ])

      assert {:ok, [{^target0, :random}]} =
               Router.find_healthy_targets(table, listener, "www.example.com")
    end
  end
end
