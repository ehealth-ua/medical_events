defmodule Core.Observations.Component do
  @moduledoc false

  use Core.Schema
  alias Core.CodeableConcept

  embedded_schema do
    field(:code, reference: [path: "code"])
    field(:reference_range, reference: [path: "reference_range"])
    field(:value)
    field(:interpretation, reference: [path: "interpretation"])
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"interpretation", v} -> {:interpretation, CodeableConcept.create(v)}
        {"code", v} -> {:code, CodeableConcept.create(v)}
        {k, v} -> {String.to_atom(k), v}
      end)
    )
  end
end
