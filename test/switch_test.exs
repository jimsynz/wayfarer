defmodule SwitchTest do
  use ExUnit.Case
  doctest Switch

  test "greets the world" do
    assert Switch.hello() == :world
  end
end
