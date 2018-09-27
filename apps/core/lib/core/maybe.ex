defmodule Core.Maybe do
  @moduledoc false

  def map(value, function, default \\ nil)
  def map(nil, _function, default), do: default
  def map(value, function, _default), do: function.(value)

  def map_list(nil, _function), do: []
  def map_list(values, function) when is_list(values), do: Enum.map(values, &function.(&1))
end
