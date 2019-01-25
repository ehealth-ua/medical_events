defmodule Core.Patients.RiskAssessments.Prediction do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.Patients.RiskAssessments.Probability
  alias Core.Patients.RiskAssessments.When

  embedded_schema do
    field(:outcome, presence: true)
    field(:probability)
    field(:qualitative_risk)
    field(:relative_risk)
    field(:when, reference: [path: "when"])
    field(:rationale)
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"outcome", v} ->
          {:outcome, CodeableConcept.create(v)}

        {"probability", %{"type" => type, "value" => value}} ->
          {:probability, Probability.create(type, value)}

        {"probability_decimal", value} ->
          {:probability, Probability.create("probability_decimal", value)}

        {"probability_range", value} ->
          {:probability, Probability.create("probability_range", value)}

        {"qualitative_risk", v} ->
          {:qualitative_risk, CodeableConcept.create(v)}

        {"when", %{"type" => type, "value" => value}} ->
          {:when, When.create(type, value)}

        {"when_period", value} ->
          {:when, When.create("when_period", value)}

        {"when_range", value} ->
          {:when, When.create("when_range", value)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end

defimpl Vex.Blank, for: Core.Patients.RiskAssessments.Prediction do
  def blank?(%Core.Patients.RiskAssessments.Prediction{}), do: false
  def blank?(_), do: true
end
