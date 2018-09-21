defmodule Core.Observations.Component do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.Observations.ReferenceRange
  alias Core.Observations.Value

  embedded_schema do
    field(:code, presence: true, reference: [path: "code"])
    field(:value, presence: true)
    field(:reference_ranges, reference: [path: "reference_ranges"])
    field(:interpretation, reference: [path: "interpretation"])
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"interpretation", v} ->
          {:interpretation, CodeableConcept.create(v)}

        {"code", v} ->
          {:code, CodeableConcept.create(v)}

        {"value", %{"type" => type, "value" => value}} ->
          {:value, Value.create(type, value)}

        {"value_" <> type, value} ->
          {:value, Value.create(type, value)}

        {"reference_ranges", v} ->
          {:reference_ranges, Enum.map(v, &ReferenceRange.create/1)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
