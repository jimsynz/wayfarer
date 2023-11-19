defmodule Wayfarer.TargetTest do
  @moduledoc false
  use ExUnit.Case, async: false
  use Support.PortTracker
  alias Support.HttpServer

  alias Wayfarer.Target
  import IP.Sigil

  setup do
    start_supervised!(Target.Supervisor)

    :ok
  end

  describe "start_link/1" do
    test "it can start a target checker" do
      port = random_port()

      assert {:ok, pid} =
               Target.start_link(
                 scheme: :http,
                 address: ~i"127.0.0.1",
                 port: port,
                 module: Support.Example
               )

      assert {:ok, :initial} = Target.current_status(pid)
    end

    test "it becomes healthy when the target is okay" do
      port = random_port()

      HttpServer.start_link(port, 200, "OK", self())

      assert {:ok, pid} =
               Target.start_link(
                 scheme: :http,
                 address: ~i"127.0.0.1",
                 port: port,
                 module: Support.Example,
                 health_checks: [[interval: 10, threshold: 3]]
               )

      assert {:ok, :initial} = Target.current_status(pid)

      HttpServer.await_requests(3)

      assert {:ok, :healthy} = Target.current_status(pid)
    end
  end

  test "it becomes unhealthy when the target is not okay" do
    port = random_port()

    HttpServer.start_link(port, 500, "ISE", self())

    assert {:ok, pid} =
             Target.start_link(
               scheme: :http,
               address: ~i"127.0.0.1",
               port: port,
               module: Support.Example,
               health_checks: [[interval: 10, threshold: 3]]
             )

    assert {:ok, :initial} = Target.current_status(pid)

    HttpServer.await_requests(2)

    assert {:ok, :unhealthy} = Target.current_status(pid)
  end
end
