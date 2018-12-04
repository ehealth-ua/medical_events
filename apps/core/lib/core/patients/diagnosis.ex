defmodule Core.Diagnosis do
  @moduledoc false

  use Core.Schema
  alias Core.CodeableConcept
  alias Core.Reference

  embedded_schema do
    field(:condition, presence: true, reference: [path: "condition"])
    field(:role, presence: true, reference: [path: "role"])
    field(:rank)
    field(:code, dictionary_reference: [referenced_field: "system", field: "code"])
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"condition", v} -> {:condition, Reference.create(v)}
        {"role", v} -> {:role, CodeableConcept.create(v)}
        {"code", v} -> {:code, CodeableConcept.create(v)}
        {k, v} -> {String.to_atom(k), v}
      end)
    )
  end
end
