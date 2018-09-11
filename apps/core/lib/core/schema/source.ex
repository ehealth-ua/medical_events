defmodule Core.Source do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:type, presence: true)
    field(:value, presence: true, reference: [path: "value"])
  end
end

defimpl Vex.Blank, for: Core.Source do
  def blank?(%Core.Source{}), do: false
  def blank?(_), do: true
end
