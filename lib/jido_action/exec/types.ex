defmodule Jido.Exec.Types do
  @moduledoc """
  Shared type definitions for the `Jido.Exec` execution modules.
  """

  alias Jido.Exec.AsyncRef

  @type action :: module()
  @type params :: map()
  @type context :: map()
  @type run_opts :: keyword()

  @type async_ref :: AsyncRef.t()
  @type legacy_async_ref :: AsyncRef.legacy_await_map()
  @type legacy_cancel_async_ref :: AsyncRef.legacy_cancel_map()
  @type async_ref_input :: async_ref() | legacy_async_ref()
  @type cancel_async_ref_input :: async_ref() | legacy_cancel_async_ref()

  @type exec_success :: {:ok, map()}
  @type exec_success_dir :: {:ok, map(), any()}
  @type exec_error :: {:error, Exception.t()}
  @type exec_error_dir :: {:error, Exception.t(), any()}

  @type exec_result ::
          exec_success
          | exec_success_dir
          | exec_error
          | exec_error_dir
end
