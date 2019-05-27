defmodule Core.Observations.Value do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.Observations.Values.Quantity
  alias Core.Observations.Values.Ratio
  alias Core.Observations.Values.SampledData
  alias Core.Period
  alias Core.Range
  import Ecto.Changeset

  @fields_required ~w()a
  @fields_optional ~w(value_string value_time value_boolean value_date_time)a

  @primary_key false
  embedded_schema do
    field(:value_string, :string)
    field(:value_time, :string)
    field(:value_boolean, :boolean)
    field(:value_date_time, :utc_datetime_usec)

    embeds_one(:value_quantity, Quantity)
    embeds_one(:value_codeable_concept, CodeableConcept)
    embeds_one(:value_sampled_data, SampledData)
    embeds_one(:value_range, Range)
    embeds_one(:value_ratio, Ratio)
    embeds_one(:value_period, Period)
  end

  def changeset(%__MODULE__{} = value, params) do
    value
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:value_quantity)
    |> cast_embed(:value_codeable_concept)
    |> cast_embed(:value_sampled_data)
    |> cast_embed(:value_range)
    |> cast_embed(:value_ratio)
    |> cast_embed(:value_period)
  end
end
