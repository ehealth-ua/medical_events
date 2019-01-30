defmodule Core.Patients.RiskAssessments.Reason do
  @moduledoc false

  use Core.Schema
  alias Core.CodeableConcept
  alias Core.Reference

  embedded_schema do
    field(:type, presence: true)
    field(:value, presence: true, reference: [path: "value"])
  end

  def create("reason_codes" = type, value) do
    %__MODULE__{type: type, value: Enum.map(value, &CodeableConcept.create/1)}
  end

  def create("reason_references" = type, value) do
    %__MODULE__{type: type, value: Enum.map(value, &Reference.create/1)}
  end
end

defimpl Vex.Blank, for: Core.Patients.RiskAssessments.Reason do
  def blank?(%Core.Patients.RiskAssessments.Reason{}), do: false
  def blank?(_), do: true
end
