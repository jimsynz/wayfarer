defmodule Wayfarer.Server.DynamicTest do
  use ExUnit.Case, async: true

  alias Wayfarer.{Listener, Server, Target}
  use Support.PortTracker
  use Support.HttpRequest
  import IP.Sigil

  defmodule DynamicServer1 do
    use Wayfarer.Server
  end

  defmodule DynamicServer2 do
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
end
