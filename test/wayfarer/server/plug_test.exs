defmodule Wayfarer.Server.PlugTest do
  @moduledoc false
  use ExUnit.Case, async: false
  use Mimic
  use Plug.Test
  use Support.PortTracker
  alias Support.HttpServer
  alias Wayfarer.Router
  alias Wayfarer.Server.Plug, as: SUT
  alias Wayfarer.Target.Selector

  setup do
    {:ok, table} = Router.init(Support.Example)

    start_supervised!(Wayfarer.Server.Supervisor)
    start_supervised!(Wayfarer.Target.Supervisor)

    {:ok, table: table}
  end

  describe "init/1" do
    test "it mappifies it's argument" do
      assert %{a: 1} == SUT.init(a: 1)
    end
  end

  describe "call/2" do
    test "it results in a bad gateway when the config map contains a wayfarer module" do
      conn =
        :gen
        |> conn("/")
        |> SUT.call(%{})

      assert conn.status == 502
    end

    test "it stores the listener config in the conn private" do
      port = random_port()

      conn =
        :get
        |> conn("/")
        |> SUT.call(%{
          module: Support.Example,
          scheme: :http,
          address: {127, 0, 0, 1},
          port: port
        })

      assert conn.private.wayfarer.listener == %{
               module: Support.Example,
               port: port,
               scheme: :http,
               address: {127, 0, 0, 1}
             }
    end

    test "it looks for healthy targets in the router" do
      listener = {:http, {127, 0, 0, 1}, random_port()}
      target = {:http, {127, 0, 0, 1}, random_port(), :auto}

      {:ok, _} = HttpServer.start_link(elem(target, 2), 200, "OK")

      Router
      |> expect(:find_healthy_targets, fn module, ^listener, host ->
        assert module == Support.Example
        assert host == "www.example.com"

        {:ok, [{target, :random}]}
      end)

      :get
      |> conn("/")
      |> SUT.call(%{
        module: Support.Example,
        scheme: elem(listener, 0),
        address: elem(listener, 1),
        port: elem(listener, 2)
      })
    end

    test "it selects a target to proxy to" do
      listener = {:http, {127, 0, 0, 1}, random_port()}
      target = {:http, {127, 0, 0, 1}, random_port(), :auto}

      {:ok, _} = HttpServer.start_link(elem(target, 2), 200, "OK")

      Router
      |> stub(:find_healthy_targets, fn _, _, _ -> {:ok, [{target, :random}]} end)

      Selector
      |> expect(:choose, fn _conn, targets, :random ->
        assert targets == [target]
        {:ok, target}
      end)

      :get
      |> conn("/")
      |> SUT.call(%{
        module: Support.Example,
        scheme: elem(listener, 0),
        address: elem(listener, 1),
        port: elem(listener, 2)
      })
    end
  end
end
