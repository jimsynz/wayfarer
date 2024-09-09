defmodule Wayfarer.Listener.RegistryTest do
  @moduledoc false
  use ExUnit.Case, async: false
  alias Wayfarer.{Error.Listener.NoSuchListener, Listener, Server, Target}
  use Support.PortTracker
  use Support.HttpRequest
  import IP.Sigil

  defmodule DynamicServer do
    @moduledoc false
    use Wayfarer.Server
  end

  setup do
    start_supervised!(Server.Supervisor)
    start_supervised!(Listener.Supervisor)
    start_supervised!(Target.Supervisor)
    start_supervised!(DynamicServer)

    :ok
  end

  describe "listener/1" do
    test "it registers the calling process with the default status" do
      listener = make_listener()

      assert :ok = Listener.Registry.register(listener)

      assert {:ok, :starting} = Listener.Registry.get_status(listener)
    end
  end

  describe "listener/2" do
    test "it registers the calling process with the provided status" do
      listener = make_listener()

      assert :ok = Listener.Registry.register(listener, :accepting_connections)

      assert {:ok, :accepting_connections} = Listener.Registry.get_status(listener)
    end
  end

  describe "list_listeners_for_module/1" do
    test "when there are listeners running, it returns them" do
      Server.add_listener(DynamicServer,
        scheme: :http,
        address: ~i"127.0.0.1",
        port: random_port()
      )

      Server.add_listener(DynamicServer,
        scheme: :http,
        address: ~i"127.0.0.1",
        port: random_port()
      )

      assert [%Listener{}, %Listener{}] =
               Listener.Registry.list_listeners_for_module(DynamicServer)
    end

    test "when there are no listeners running, it returns an empty list" do
      assert [] = Listener.Registry.list_listeners_for_module(DynamicServer)
    end
  end

  describe "get_status/1" do
    test "when the listener exists it returns the status of the listener" do
      port = random_port()

      Server.add_listener(DynamicServer,
        scheme: :http,
        address: ~i"127.0.0.1",
        port: port
      )

      listener = make_listener(port)

      assert {:ok, :accepting_connections} = Listener.Registry.get_status(listener)
    end

    test "when the listener doesn't exist it returns an error" do
      listener = make_listener()
      assert {:error, %NoSuchListener{}} = Listener.Registry.get_status(listener)
    end
  end

  describe "get_pid/1" do
    test "when the listener exists it returns the pid of the listener" do
      port = random_port()

      Server.add_listener(DynamicServer,
        scheme: :http,
        address: ~i"127.0.0.1",
        port: port
      )

      listener = make_listener(port)

      assert {:ok, pid} = Listener.Registry.get_pid(listener)
      assert is_pid(pid)
    end

    test "when the listener doesn't exist it returns an error" do
      listener = make_listener()
      assert {:error, %NoSuchListener{}} = Listener.Registry.get_status(listener)
    end
  end

  describe "update_status/2" do
    test "when the listener exists it updates the status of the listener" do
      listener = make_listener()

      assert :ok = Listener.Registry.register(listener, :accepting_connections)
      assert {:ok, :accepting_connections} = Listener.Registry.get_status(listener)

      assert :ok = Listener.Registry.update_status(listener, :draining)
      assert {:ok, :draining} = Listener.Registry.get_status(listener)
    end

    test "when the listener doesn't exist it returns an error" do
      listener = make_listener()
      assert {:error, %NoSuchListener{}} = Listener.Registry.update_status(listener, :draining)
    end
  end

  defp make_listener(port \\ random_port()) do
    %Listener{
      scheme: :http,
      address: ~i"127.0.0.1",
      port: port,
      module: DynamicServer
    }
  end
end
