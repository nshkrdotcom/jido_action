defmodule Jido.Tools.Weather.Config do
  @moduledoc false

  @default_periods 7

  @spec default_periods() :: pos_integer()
  def default_periods, do: @default_periods
end
