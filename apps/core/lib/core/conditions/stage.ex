defmodule Core.Stage do
  @moduledoc false

  use Core.Schema
  alias Core.CodeableConcept

  embedded_schema do
    field(:summary, dictionary_reference: [path: "summary", referenced_field: "system", field: "code"])
  end

  def create(data) do
    %__MODULE__{
      summary: CodeableConcept.create(Map.get(data, "summary"))
    }
  end
end
