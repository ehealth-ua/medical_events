defmodule Core.CodeableConcept do
  @moduledoc false

  use Core.Schema
  alias Core.Coding

  embedded_schema do
    field(:coding, presence: true, reference: [path: "coding"])
    field(:text)
  end

  def create(nil), do: nil

  def create(data) do
    %__MODULE__{coding: Enum.map(Map.get(data, "coding"), &Coding.create/1), text: Map.get(data, "text")}
  end
end

defimpl Vex.Blank, for: Core.CodeableConcept do
  def blank?(%Core.CodeableConcept{}), do: false
  def blank?(_), do: true
end
