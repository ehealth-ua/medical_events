defmodule Core.Patients.RiskAssessments.Prediction do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.Patients.RiskAssessments.Probability
  alias Core.Patients.RiskAssessments.When
  import Ecto.Changeset

  @fields_required ~w()a
  @fields_optional ~w(relative_risk rationale)a

  @primary_key false
  embedded_schema do
    field(:rationale, :string)
    field(:relative_risk, :float)

    embeds_one(:outcome, CodeableConcept)
    embeds_one(:probability, Probability)
    embeds_one(:qualitative_risk, CodeableConcept)
    embeds_one(:when, When)
  end

  def changeset(%__MODULE__{} = prediction, params) do
    prediction
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:outcome)
    |> cast_embed(:probability)
    |> cast_embed(:qualitative_risk)
    |> cast_embed(:when)
  end
end
