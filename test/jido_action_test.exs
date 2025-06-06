defmodule JidoActionTest do
  use ExUnit.Case
  doctest JidoAction

  test "greets the world" do
    assert JidoAction.hello() == :world
  end
end
