defmodule Wayfarer.Server.ProxyTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Mint.HTTP
  alias Wayfarer.Server.Proxy
  alias Wayfarer.Target.ActiveConnections

  use Mimic
  use Plug.Test
  use Support.PortTracker

  import IP.Sigil

  setup do
    start_supervised!(Wayfarer.Target.Supervisor)

    listener = {:http, {127, 0, 0, 1}, random_port()}
    peer_data = %{address: {192, 0, 2, 2}, port: random_port(), ssl_cert: nil}

    conn =
      :get
      |> conn("/")
      |> put_private(:wayfarer, %{
        listener: %{
          scheme: elem(listener, 0),
          address: elem(listener, 1),
          port: elem(listener, 2)
        }
      })
      |> put_peer_data(peer_data)
      |> put_req_header("accept", "*/*")

    {:ok, listener: listener, conn: conn, peer: peer_data}
  end

  defp stub_request(HTTP, responses \\ [:done]) do
    req = make_ref()

    responses =
      responses
      |> Enum.map(fn
        :done -> {:done, req}
        {:status, status} -> {:status, req, status}
        {:headers, headers} -> {:headers, req, headers}
        {:data, chunk} -> {:data, req, chunk}
        {:error, reason} -> {:error, req, reason}
      end)

    HTTP
    |> stub(:connect, fn _, _, _, _ -> {:ok, :fake_conn} end)
    |> stub(:request, fn mint, _, _, _, _ ->
      send(self(), :ignore)
      {:ok, mint, req}
    end)
    |> stub(:stream, fn mint, :ignore -> {:ok, mint, responses} end)
    |> stub(:stream, fn mint, _ -> {:ok, mint, [{:done, req}]} end)
  end

  describe "request/2" do
    test "it opens an HTTP connection to the target and sends the request", %{conn: conn} do
      target = {:http, {127, 0, 0, 1}, random_port()}
      req = make_ref()

      HTTP
      |> expect(:connect, fn scheme, address, port, options ->
        assert scheme == elem(target, 0)
        assert address == elem(target, 1)
        assert port == elem(target, 2)
        assert options[:hostname] == "www.example.com"
        assert options[:timeout] == 5000

        {:ok, :fake_conn}
      end)
      |> expect(:request, fn mint, _, _, _, _ ->
        send(self(), :ignore)
        {:ok, mint, req}
      end)
      |> expect(:stream, fn mint, :ignore ->
        {:ok, mint, [{:done, req}]}
      end)

      assert conn = Proxy.request(conn, target)
      assert conn.halted
    end

    test "it records the outgoing connection", %{conn: conn} do
      target = {:http, {127, 0, 0, 1}, random_port()}

      ActiveConnections
      |> expect(:connect, fn ^target -> :ok end)

      HTTP
      |> stub_request()

      assert conn = Proxy.request(conn, target)
      assert conn.halted
    end

    test "when there is a connection error, it returns a bad gateway error", %{conn: conn} do
      HTTP
      |> stub(:connect, fn _, _, _, _ ->
        {:error, %Mint.TransportError{reason: :protocol_not_negotiated}}
      end)

      target = {:http, {127, 0, 0, 1}, random_port()}
      assert conn = Proxy.request(conn, target)
      assert conn.status == 502
    end

    test "when there is a timeout during connection, it returns a gateway timeout error", %{
      conn: conn
    } do
      HTTP
      |> stub(:connect, fn _, _, _, _ ->
        {:error, %Mint.TransportError{reason: :timeout}}
      end)

      target = {:http, {127, 0, 0, 1}, random_port()}
      assert conn = Proxy.request(conn, target)
      assert conn.status == 504
    end

    test "it injects the correct `forwarded` header", %{
      conn: conn,
      peer: peer,
      listener: listener
    } do
      HTTP
      |> stub(:connect, fn _, _, _, _ -> {:ok, :fake_conn} end)
      |> stub(:request, fn _, _, _, headers, _ ->
        [forwarded] =
          headers
          |> parse_forwarded_headers()

        assert forwarded[:by] == "#{:inet.ntoa(elem(listener, 1))}:#{elem(listener, 2)}"
        assert forwarded[:for] == "#{:inet.ntoa(peer.address)}:#{peer.port}"
        assert forwarded[:host] == "www.example.com"
        assert forwarded[:proto] == "http"

        {:error, :ignore}
      end)

      target = {:http, {127, 0, 0, 1}, random_port()}
      Proxy.request(conn, target)
    end

    test "when the listener and peer are IPv6 address, it injects the correct `forwarded` header",
         %{conn: conn, peer: peer, listener: listener} do
      peer = %{peer | address: IP.Address.to_tuple(~i"2001:db8::1")}
      listener = put_elem(listener, 1, IP.Address.to_tuple(~i"2001:db8::2"))

      conn =
        conn
        |> put_peer_data(peer)
        |> put_private(:wayfarer, %{
          listener: %{
            scheme: elem(listener, 0),
            address: elem(listener, 1),
            port: elem(listener, 2)
          }
        })

      HTTP
      |> stub(:connect, fn _, _, _, _ -> {:ok, :fake_conn} end)
      |> stub(:request, fn _, _, _, headers, _ ->
        [forwarded] =
          headers
          |> parse_forwarded_headers()

        assert forwarded[:by] == "[#{:inet.ntoa(elem(listener, 1))}]:#{elem(listener, 2)}"
        assert forwarded[:for] == "[#{:inet.ntoa(peer.address)}]:#{peer.port}"
        assert forwarded[:host] == "www.example.com"
        assert forwarded[:proto] == "http"

        {:error, :ignore}
      end)

      target = {:http, {127, 0, 0, 1}, random_port()}
      Proxy.request(conn, target)
    end

    test "when the request has already been forwarded by another proxy, it still injects the correct `forwarded` header",
         %{conn: conn, peer: peer, listener: listener} do
      origin_header =
        "by=[2001:db8::1]:#{random_port()};for=[2001:db8::2]:#{random_port()};host=test.example.com;proto=https"

      conn = put_req_header(conn, "forwarded", origin_header)
      [origin_header] = parse_forwarded_headers([{"forwarded", origin_header}])

      HTTP
      |> stub(:connect, fn _, _, _, _ -> {:ok, :fake_conn} end)
      |> stub(:request, fn _, _, _, headers, _ ->
        [forwarded, origin] =
          headers
          |> parse_forwarded_headers()

        assert forwarded[:by] == "#{:inet.ntoa(elem(listener, 1))}:#{elem(listener, 2)}"
        assert forwarded[:for] == "#{:inet.ntoa(peer.address)}:#{peer.port}"
        assert forwarded[:host] == "www.example.com"
        assert forwarded[:proto] == "http"

        assert origin == origin_header

        {:error, :ignore}
      end)

      target = {:http, {127, 0, 0, 1}, random_port()}
      Proxy.request(conn, target)
    end
  end

  defp parse_forwarded_headers(headers) do
    headers
    |> Enum.filter(&(elem(&1, 0) == "forwarded"))
    |> Enum.map(fn {_, header} ->
      header
      |> String.split(";")
      |> Enum.map(&parse_forwarded_header/1)
    end)
  end

  defp parse_forwarded_header(header) do
    header
    |> String.split("=")
    |> case do
      ["by", f_by] -> {:by, f_by}
      ["for", f_for] -> {:for, f_for}
      ["host", host] -> {:host, host}
      ["proto", proto] -> {:proto, proto}
    end
  end
end
