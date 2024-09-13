defmodule Wayfarer.Server.DynamicTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Wayfarer.{Error.Listener.NoSuchListener, Listener, Server, Target}
  use Support.PortTracker
  use Support.HttpRequest
  import IP.Sigil

  defmodule DynamicServer1 do
    @moduledoc false
    use Wayfarer.Server
  end

  defmodule DynamicServer2 do
    @moduledoc false
    use Wayfarer.Server
  end

  setup do
    start_supervised!(Server.Supervisor)
    start_supervised!(Listener.Supervisor)
    start_supervised!(Target.Supervisor)
    start_supervised!(DynamicServer1)
    start_supervised!(DynamicServer2)

    :ok
  end

  describe "Server.add_listener/2" do
    test "a listener can be dynamically added to a server" do
      port = random_port()

      assert {:ok, _pid} =
               Server.add_listener(DynamicServer1,
                 scheme: :http,
                 address: ~i"127.0.0.1",
                 port: port
               )

      assert {:ok, %{status: 502}} = request(:http, ~i"127.0.0.1", port, host: "www.example.com")
    end

    test "the same listener cannot be added to two servers" do
      port = random_port()

      assert {:ok, _pid} =
               Server.add_listener(DynamicServer1,
                 scheme: :http,
                 address: ~i"127.0.0.1",
                 port: port
               )

      assert {:error, _} =
               Server.add_listener(DynamicServer2,
                 scheme: :http,
                 address: ~i"127.0.0.1",
                 port: port
               )
    end
  end

  describe "Server.list_listeners/1" do
    test "when there are no listeners it returns an empty list" do
      assert [] = Server.list_listeners(DynamicServer1)
    end

    test "when there are listeners running it returns a list" do
      port = random_port()

      assert {:ok, _pid} =
               Server.add_listener(DynamicServer1,
                 scheme: :http,
                 address: ~i"127.0.0.1",
                 port: port
               )

      assert [%Listener{} = listener] =
               Server.list_listeners(DynamicServer1)

      assert listener.scheme == :http
      assert listener.address == ~i"127.0.0.1"
      assert listener.port == port
    end
  end

  describe "Server.remove_listener/2" do
    test "when there are no listeners running it returns an error" do
      listener = %Listener{scheme: :http, address: ~i"127.0.0.1", port: random_port()}
      assert {:error, %NoSuchListener{}} = Server.remove_listener(DynamicServer1, listener)
    end

    test "when there listeners running they are asked to stop" do
      port = random_port()

      assert {:ok, pid} =
               Server.add_listener(DynamicServer1,
                 scheme: :http,
                 address: ~i"127.0.0.1",
                 port: port
               )

      [listener] = Server.list_listeners(DynamicServer1)

      assert {:ok, :draining} = Server.remove_listener(DynamicServer1, listener)

      refute Process.alive?(pid)
    end
  end

  describe "Server.add_target/2" do
    test "a target can be dynamically added to a server" do
      port = random_port()

      assert {:ok, _pid} =
               Server.add_target(DynamicServer1,
                 scheme: :http,
                 port: port,
                 address: ~i"127.0.0.1"
               )

      assert [target] = Target.Registry.list_targets_for_module(DynamicServer1)
      assert target.port == port
    end
  end

  describe "Server.list_targets/1" do
    test "running targets are returned" do
      port = random_port()

      assert {:ok, _pid} =
               Server.add_target(DynamicServer1,
                 scheme: :http,
                 port: port,
                 address: ~i"127.0.0.1"
               )

      assert [target] = Server.list_targets(DynamicServer1)
      assert target.port == port
    end
  end
end
