defmodule Core.Maybe do
  @moduledoc false

  def map(value, function, default \\ nil)
  def map(nil, _function, default), do: default
  def map(value, function, _default), do: function.(value)
end
