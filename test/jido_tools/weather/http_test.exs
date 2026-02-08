defmodule JidoTest.Tools.Weather.HTTPTest do
  use JidoTest.ActionCase, async: false

  import Mimic

  alias Jido.Action.Error
  alias Jido.Tools.Weather.HTTP

  setup :set_mimic_global
  setup :verify_on_exit!

  test "applies timeout budget to request options" do
    expect(Req, :request!, fn opts ->
      assert opts[:receive_timeout] == 321
      assert opts[:pool_timeout] == 321
      assert opts[:connect_options] == [timeout: 321]

      %{status: 200, body: %{}, headers: %{}}
    end)

    assert {:ok, %{status: 200}} = HTTP.get("https://example.com", context: %{timeout: 321})
  end

  test "returns timeout error when deadline has already elapsed" do
    expired_deadline_ms = System.monotonic_time(:millisecond) - 1

    assert {:error, %Error.TimeoutError{timeout: 0}} =
             HTTP.get("https://example.com",
               context: %{__jido_exec_deadline_ms__: expired_deadline_ms}
             )
  end
end
