defmodule Core.CodeableConcept do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:coding, presence: true)
    field(:text)
  end

  def create_codeable_concept(data) do
    struct(__MODULE__, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end
