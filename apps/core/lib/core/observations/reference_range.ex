defmodule Core.Observations.ReferenceRange do
  @moduledoc false

  use Core.Schema
  alias Core.CodeableConcept

  embedded_schema do
    field(:low)
    field(:high)
    field(:type, reference: [path: "applies_to"])
    field(:applies_to, reference: [path: "applies_to"])
    field(:age)
    field(:text)
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"type", v} -> {:type, CodeableConcept.create(v)}
        {"applies_to", v} -> {:applies_to, Enum.map(v, &CodeableConcept.create/1)}
        {k, v} -> {String.to_atom(k), v}
      end)
    )
  end
end
