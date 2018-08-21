defmodule Core.Identifier do
  @moduledoc false

  use Core.Schema
  alias Core.CodeableConcept

  embedded_schema do
    field(:type, presence: true)
    field(:value, presence: true)
  end

  def create(data) do
    %__MODULE__{type: CodeableConcept.create(Map.get(data, "type")), value: Map.get(data, "value")}
  end
end

defimpl Vex.Blank, for: Core.Identifier do
  def blank?(%Core.Identifier{}), do: false
  def blank?(_), do: true
end
