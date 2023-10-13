defmodule WayfarerTest do
  use ExUnit.Case
  doctest Wayfarer

  test "greets the world" do
    assert Wayfarer.hello() == :world
  end
end
