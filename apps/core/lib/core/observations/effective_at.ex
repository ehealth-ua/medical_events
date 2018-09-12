defmodule Core.Observations.EffectiveAt do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:type, presence: true)
    field(:value, presence: true, reference: [path: "value"])
  end
end

defimpl Vex.Blank, for: Core.Observations.EffectiveAt do
  def blank?(%Core.Observations.EffectiveAt{}), do: false
  def blank?(_), do: true
end
