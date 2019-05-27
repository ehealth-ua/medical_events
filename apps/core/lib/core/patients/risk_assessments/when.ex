defmodule Core.Patients.RiskAssessments.When do
  @moduledoc false

  use Ecto.Schema
  alias Core.Period
  alias Core.Range
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_one(:when_period, Period)
    embeds_one(:when_range, Range)
  end

  def changeset(%__MODULE__{} = value, params) do
    value
    |> cast(params, [])
    |> cast_embed(:when_period)
    |> cast_embed(:when_range)
  end
end
