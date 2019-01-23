defmodule Core.Patients.RiskAssessments.Probability do
  @moduledoc false

  use Core.Schema
  alias Core.Range

  embedded_schema do
    field(:type, presence: true)
    field(:value, presence: true, reference: [path: "value"])
  end

  def create("probability_decimal" = type, value) do
    %__MODULE__{type: type, value: value}
  end

  def create("probability_range" = type, value) do
    %__MODULE__{type: type, value: Range.create(value)}
  end
end

defimpl Vex.Blank, for: Core.Patients.RiskAssessments.Probability do
  def blank?(%Core.Patients.RiskAssessments.Probability{}), do: false
  def blank?(_), do: true
end
