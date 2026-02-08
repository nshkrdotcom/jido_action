defmodule JidoTest.Tools.Weather.ConfigTest do
  use ExUnit.Case, async: true

  alias Jido.Tools.Weather.Config

  test "default_periods/0 returns the documented default" do
    assert Config.default_periods() == 7
  end
end
