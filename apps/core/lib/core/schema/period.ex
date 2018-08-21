defmodule Core.Period do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:start, presence: true)
    field(:end)
  end

  def create(data) do
    struct(__MODULE__, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end

defimpl Vex.Blank, for: Core.Period do
  def blank?(%Core.Period{}), do: false
  def blank?(_), do: true
end
