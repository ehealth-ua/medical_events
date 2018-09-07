defmodule Core.Observations.Values.Range do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:low, presence: true)
    field(:high, presence: true)
  end

  def create(data) do
    struct(__MODULE__, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end
