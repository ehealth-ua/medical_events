defmodule Core.Patients.RiskAssessments.Probability do
  @moduledoc false

  use Ecto.Schema
  alias Core.Range
  import Ecto.Changeset

  @fields_required ~w()a
  @fields_optional ~w(probability_decimal)a

  @primary_key false
  embedded_schema do
    field(:probability_decimal, :float)
    embeds_one(:probability_range, Range)
  end

  def changeset(%__MODULE__{} = probability, params) do
    probability
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:probability_range)
  end
end
