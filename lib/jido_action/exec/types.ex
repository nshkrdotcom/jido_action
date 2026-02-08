defmodule Jido.Exec.Types do
  @moduledoc """
  Shared type definitions for the `Jido.Exec` execution modules.
  """

  @type action :: module()
  @type params :: map()
  @type context :: map()
  @type run_opts :: keyword()

  @type async_ref :: %{
          required(:ref) => reference(),
          required(:pid) => pid(),
          optional(:monitor_ref) => reference(),
          optional(:owner) => pid()
        }

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
