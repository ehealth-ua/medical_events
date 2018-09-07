defmodule Core.Observations.Values.Quantity do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:value, presence: true)
    field(:comparator)
    field(:unit, presence: true)
    field(:system)
    field(:code)
  end

  def create(data) do
    struct(__MODULE__, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end
