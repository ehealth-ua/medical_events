defmodule Core.Evidence do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.Reference

  embedded_schema do
    field(:codes, reference: [path: "codes"])
    field(:details, reference: [path: "details"])
  end

  def create(data) do
    %__MODULE__{
      codes: Enum.map(Map.get(data, "codes"), &CodeableConcept.create/1),
      details: Enum.map(Map.get(data, "details"), &Reference.create/1)
    }
  end
end
