defmodule Core.Patients.Immunizations.Explanation do
  @moduledoc false

  use Core.Schema
  alias Core.CodeableConcept

  embedded_schema do
    field(:type, presence: true)
    field(:value, presence: true, reference: [path: "value"])
  end

  def create(%{"reasons" => reasons}) do
    %__MODULE__{type: "reasons", value: Enum.map(reasons, &CodeableConcept.create/1)}
  end

  def create(%{"reasons_not_given" => reasons_not_given}) do
    %__MODULE__{type: "reasons_not_given", value: Enum.map(reasons_not_given, &CodeableConcept.create/1)}
  end
end

defimpl Vex.Blank, for: Core.Patients.Immunizations.Explanation do
  def blank?(%Core.Patients.Immunizations.Explanation{}), do: false
  def blank?(_), do: true
end
