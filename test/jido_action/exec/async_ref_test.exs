defmodule JidoTest.Exec.AsyncRefTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Jido.Exec.AsyncRef

  @moduletag :capture_log

  describe "from_legacy_cancel_map/3" do
    test "disables result flushing when legacy cancel map is missing :ref" do
      legacy_ref = %{pid: self(), owner: self(), result_tag: :legacy_result}

      capture_log(fn ->
        converted_ref = AsyncRef.from_legacy_cancel_map(legacy_ref, Jido.Exec.Async, :default_tag)
        send(self(), {:converted_ref, converted_ref})
      end)

      assert_receive {:converted_ref, async_ref}

      assert is_reference(async_ref.ref)
      assert async_ref.result_tag == nil
    end

    test "preserves result tag when legacy cancel map includes :ref" do
      ref = make_ref()
      legacy_ref = %{pid: self(), ref: ref, owner: self(), result_tag: :legacy_result}

      capture_log(fn ->
        converted_ref = AsyncRef.from_legacy_cancel_map(legacy_ref, Jido.Exec.Async, :default_tag)
        send(self(), {:converted_ref, converted_ref})
      end)

      assert_receive {:converted_ref, async_ref}

      assert async_ref.ref == ref
      assert async_ref.result_tag == :legacy_result
    end
  end
end
