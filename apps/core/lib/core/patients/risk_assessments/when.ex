defmodule Core.Patients.RiskAssessments.When do
  @moduledoc false

  use Core.Schema
  alias Core.Period
  alias Core.Range

  embedded_schema do
    field(:type, presence: true)
    field(:value, presence: true, reference: [path: "value"])
  end

  def create("when_period" = type, value) do
    %__MODULE__{type: type, value: Period.create(value)}
  end

  def create("when_range" = type, value) do
    %__MODULE__{type: type, value: Range.create(value)}
  end
end

defimpl Vex.Blank, for: Core.Patients.RiskAssessments.When do
  def blank?(%Core.Patients.RiskAssessments.When{}), do: false
  def blank?(_), do: true
end
