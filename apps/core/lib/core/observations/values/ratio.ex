defmodule Core.Observations.Values.Ratio do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:numerator, presence: true)
    field(:denominator, presence: true)
  end

  def create(data) do
    struct(__MODULE__, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end
