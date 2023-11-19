defmodule Wayfarer.UtilsTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use Support.PortTracker
  import IP.Sigil
  import Wayfarer.Utils

  describe "sanitise_ip_address/1" do
    test "when passed a valid IPv6 string it returns the parsed tuple" do
      assert {:ok, {8193, 3512, 0, 0, 0, 0, 0, 1}} = sanitise_ip_address("2001:db8::1")
    end

    test "when passed a valid IPv4 string it returns a parsed tuple" do
      assert {:ok, {192, 0, 2, 1}} = sanitise_ip_address("192.0.2.1")
    end

    test "when passed an IP address struct it returns a tuple" do
      assert {:ok, {8193, 3512, 0, 0, 0, 0, 0, 1}} = sanitise_ip_address(~i"2001:db8::1")
    end

    test "when passed a valid IPv6 tuple it returns it" do
      assert {:ok, {8193, 3512, 0, 0, 0, 0, 0, 1}} =
               sanitise_ip_address({8193, 3512, 0, 0, 0, 0, 0, 1})
    end

    test "when passed a valid IPv4 tuple it returns it" do
      assert {:ok, {192, 0, 2, 1}} = sanitise_ip_address({192, 0, 2, 1})
    end

    test "when passed an invalid IPv4 tuple, it returns an error" do
      assert {:error, "Invalid address"} = sanitise_ip_address({192, 0, 2, 257})
    end

    test "when passed an invalid IPv6 tuple, it returns an error" do
      assert {:error, "Invalid address"} =
               sanitise_ip_address({8193, 3512, 0, 0, 0, 0, 0, 0xFFFF1})
    end
  end

  describe "sanitise_scheme/1" do
    test "when passed `:http` it is ok" do
      assert {:ok, :http} = sanitise_scheme(:http)
    end

    test "when passed `:https` it is ok" do
      assert {:ok, :https} = sanitise_scheme(:https)
    end

    test "when passed an unsupported scheme it returns an error" do
      assert {:error, _} = sanitise_scheme(:spdy)
    end
  end

  describe "to_uri/3" do
    test "when given an IPv6 address it correctly encodes the URI" do
      port = random_port()
      assert {:ok, uri} = to_uri(:http, ~i"2001:db8::1", port)
      assert "http://[2001:db8::1]:#{port}" == to_string(uri)
    end

    test "when given an IPv4 address it correctly encodes the URI" do
      port = random_port()
      assert {:ok, uri} = to_uri(:http, ~i"192.0.2.1", port)
      assert "http://192.0.2.1:#{port}" == to_string(uri)
    end
  end
end
