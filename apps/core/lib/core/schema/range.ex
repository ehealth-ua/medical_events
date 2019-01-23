defmodule Core.Range do
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

defimpl Vex.Blank, for: Core.Range do
  def blank?(%Core.Range{}), do: false
  def blank?(_), do: true
end
