defmodule Wayfarer.TargetTest do
  @moduledoc false
  use ExUnit.Case, async: false
  alias Support.HttpServer
  alias Wayfarer.Target

  setup do
    start_supervised!(Target.Supervisor)

    :ok
  end

  describe "start_target/1" do
    test "it returns an error when options are invalid" do
      assert {:error, _} =
               Target.start_target(scheme: :spdy, ip: {127, 0, 0, 1}, port: random_port())
    end

    test "it can start a target checker" do
      port = random_port()
      assert {:ok, _pid} = Target.start_target(scheme: :http, ip: {127, 0, 0, 1}, port: port)
    end

    test "it becomes healthy when the target is ok" do
      port = random_port()

      HttpServer.start_link(port, 200, "OK")

      assert {:ok, _pid} =
               Target.start_target(
                 scheme: :http,
                 ip: {127, 0, 0, 1},
                 port: port,
                 health_check: [interval: 10]
               )

      Process.sleep(200)

      assert {:ok, :healthy} = Target.Table.get_status(:http, {127, 0, 0, 1}, port)
    end

    test "it stays in initial state when the target is not ok" do
      port = random_port()

      HttpServer.start_link(port, 500, "BANG!")

      assert {:ok, _pid} =
               Target.start_target(
                 scheme: :http,
                 ip: {127, 0, 0, 1},
                 port: port,
                 health_check: [interval: 10]
               )

      Process.sleep(200)

      assert {:ok, :initial} = Target.Table.get_status(:http, {127, 0, 0, 1}, port)
    end

    test "it can transitions from healthy -> unhealthy -> healthy when the server changes state" do
      port = random_port()

      {:ok, http} = HttpServer.start_link(port, 200, "OK")

      assert {:ok, _pid} =
               Target.start_target(
                 scheme: :http,
                 ip: {127, 0, 0, 1},
                 port: port,
                 health_check: [interval: 10]
               )

      Process.sleep(500)

      assert {:ok, :healthy} = Target.Table.get_status(:http, {127, 0, 0, 1}, port)

      GenServer.stop(http, :normal)

      Process.sleep(250)

      assert {:ok, :unhealthy} = Target.Table.get_status(:http, {127, 0, 0, 1}, port)

      {:ok, http} = HttpServer.start_link(port, 200, "OK")

      Process.sleep(500)

      assert {:ok, :healthy} = Target.Table.get_status(:http, {127, 0, 0, 1}, port)
    end
  end

  defp random_port, do: :rand.uniform(0xFFFF - 1000) + 1000
end
