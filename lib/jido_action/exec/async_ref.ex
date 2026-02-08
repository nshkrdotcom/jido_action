defmodule Jido.Exec.AsyncRef do
  @moduledoc """
  Struct and compatibility helpers for asynchronous execution references.

  `Jido.Exec` now returns `%Jido.Exec.AsyncRef{}` for async operations.
  Legacy map-shaped async refs are still accepted by await/cancel functions
  during the current transition window and emit a deprecation warning.
  """

  require Logger

  @enforce_keys [:ref, :pid, :monitor_ref, :owner, :result_tag]
  defstruct [:ref, :pid, :monitor_ref, :owner, :result_tag]

  @typedoc "Canonical async reference returned by async producers."
  @type t :: %__MODULE__{
          ref: reference(),
          pid: pid(),
          monitor_ref: reference() | nil,
          owner: pid() | nil,
          result_tag: atom() | nil
        }

  @typedoc "Legacy async-ref map accepted temporarily for await operations."
  @type legacy_await_map :: %{
          required(:ref) => reference(),
          required(:pid) => pid(),
          optional(:monitor_ref) => reference(),
          optional(:owner) => pid(),
          optional(:result_tag) => atom()
        }

  @typedoc "Legacy async-ref map accepted temporarily for cancellation operations."
  @type legacy_cancel_map :: %{
          required(:pid) => pid(),
          optional(:ref) => reference(),
          optional(:monitor_ref) => reference(),
          optional(:owner) => pid(),
          optional(:result_tag) => atom()
        }

  @spec new(reference(), pid(), reference(), pid(), atom()) :: t()
  def new(ref, pid, monitor_ref, owner, result_tag) do
    %__MODULE__{
      ref: ref,
      pid: pid,
      monitor_ref: monitor_ref,
      owner: owner,
      result_tag: result_tag
    }
  end

  @spec from_legacy_await_map(legacy_await_map(), module(), atom() | nil) :: t()
  def from_legacy_await_map(
        %{ref: ref, pid: pid} = legacy_map,
        caller_module,
        default_result_tag \\ nil
      ) do
    warn_legacy_map(caller_module, :await)

    %__MODULE__{
      ref: ref,
      pid: pid,
      monitor_ref: Map.get(legacy_map, :monitor_ref),
      owner: Map.get(legacy_map, :owner),
      result_tag: Map.get(legacy_map, :result_tag, default_result_tag)
    }
  end

  @spec from_legacy_cancel_map(legacy_cancel_map(), module(), atom() | nil) :: t()
  def from_legacy_cancel_map(%{pid: pid} = legacy_map, caller_module, default_result_tag \\ nil) do
    warn_legacy_map(caller_module, :cancel)

    %__MODULE__{
      ref: Map.get(legacy_map, :ref, make_ref()),
      pid: pid,
      monitor_ref: Map.get(legacy_map, :monitor_ref),
      owner: Map.get(legacy_map, :owner),
      result_tag: Map.get(legacy_map, :result_tag, default_result_tag)
    }
  end

  @spec warn_legacy_map(module(), :await | :cancel) :: :ok
  def warn_legacy_map(caller_module, function_name) do
    Logger.warning(
      "#{inspect(caller_module)}.#{function_name}/#{async_ref_function_arity(function_name)} " <>
        "received a legacy map async_ref. Pass %Jido.Exec.AsyncRef{} instead. " <>
        "Map async_ref support is deprecated and will be removed in the next major release."
    )

    :ok
  end

  defp async_ref_function_arity(:await), do: 2
  defp async_ref_function_arity(:cancel), do: 1
end
