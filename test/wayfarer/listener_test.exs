defmodule Wayfarer.ListenerTest do
  @moduledoc false
  use ExUnit.Case, async: false
  alias Wayfarer.Listener
  import ExUnit.CaptureLog

  setup do
    start_supervised!(Wayfarer.Listener.Supervisor)

    start_supervised!(
      {Finch,
       name: :test_client,
       pools: %{
         default: [
           conn_opts: [
             transport_opts: [
               verify: :verify_none
             ]
           ]
         ]
       }}
    )

    :ok
  end

  describe "start_listener/1" do
    test "it returns an error when the scheme option is missing" do
      assert {:error, {:required_option, :scheme}} = Listener.start_listener([])
    end

    test "it returns an error when an option is incorrect" do
      assert {:error, _} = Listener.start_listener(scheme: "Marty McFly", port: random_port())
    end

    test "it can start an HTTP listener" do
      port = random_port()

      assert {:ok, _pid} =
               Listener.start_listener(
                 scheme: :http,
                 ip: {127, 0, 0, 1},
                 port: port
               )

      assert {:ok, %{status: 502}} =
               :get
               |> Finch.build("http://127.0.0.1:#{port}/")
               |> Finch.request(:test_client)
    end

    test "it can start an HTTPS listener" do
      port = random_port()

      certfile = Path.join(__DIR__, "../support/test.cert")
      keyfile = Path.join(__DIR__, "../support/test.key")

      assert {:ok, _pid} =
               Listener.start_listener(
                 scheme: :https,
                 ip: {127, 0, 0, 1},
                 port: port,
                 certfile: certfile,
                 keyfile: keyfile
               )

      assert {:ok, %{status: 502}} =
               :get
               |> Finch.build("https://127.0.0.1:#{port}/")
               |> Finch.request(:test_client)
    end

    test "it restarts listeners when they crash" do
      port = random_port()

      assert {:ok, _pid} =
               Listener.start_listener(
                 scheme: :http,
                 ip: {127, 0, 0, 1},
                 port: port
               )

      # It's up
      assert {:ok, %{status: 502}} =
               :get
               |> Finch.build("http://127.0.0.1:#{port}/")
               |> Finch.request(:test_client)

      # Crash it
      capture_log(fn ->
        [{_, pid}] = Registry.lookup(Listener.Registry, {{127, 0, 0, 1}, port})
        Process.exit(pid, :kill)
      end)

      # It's up again
      assert {:ok, %{status: 502}} =
               :get
               |> Finch.build("http://127.0.0.1:#{port}/")
               |> Finch.request(:test_client)
    end
  end

  describe "stop_listener/2" do
    test "it can shut down a listener" do
      port = random_port()

      assert {:ok, pid} =
               Listener.start_listener(
                 scheme: :http,
                 ip: {127, 0, 0, 1},
                 port: port
               )

      assert {:ok, %{status: 502}} =
               :get
               |> Finch.build("http://127.0.0.1:#{port}/")
               |> Finch.request(:test_client)

      Listener.stop_listener({127, 0, 0, 1}, port)

      wait_until_dead(pid)

      assert {:error, _} =
               :get
               |> Finch.build("http://127.0.0.1:#{port}/")
               |> Finch.request(:test_client)
    end
  end

  defp random_port, do: :rand.uniform(0xFFFF - 1000) + 1000

  defp wait_until_dead(pid) do
    if Process.alive?(pid) do
      wait_until_dead(pid)
    else
      :ok
    end
  end
end
