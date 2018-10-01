defmodule Core.Observations.ReferenceRange do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.Observations.Values.Quantity

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
        {"low", v} -> {:low, Quantity.create(v)}
        {"high", v} -> {:high, Quantity.create(v)}
        {"age", %{"low" => low, "high" => high}} -> {:age, %{low: Quantity.create(low), high: Quantity.create(high)}}
        {"age", _v} -> {:age, %{low: nil, high: nil}}
        {k, v} -> {String.to_atom(k), v}
      end)
    )
  end
end
