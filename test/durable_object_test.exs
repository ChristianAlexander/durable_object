defmodule DurableObjectTest do
  use ExUnit.Case
  doctest DurableObject

  test "greets the world" do
    assert DurableObject.hello() == :world
  end
end
