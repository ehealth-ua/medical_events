defmodule Core.Observations.Component do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.Observations.ReferenceRange
  alias Core.Observations.Value
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_one(:interpretation, CodeableConcept)
    embeds_one(:code, CodeableConcept)
    embeds_one(:value, Value)
    embeds_many(:reference_ranges, ReferenceRange)
  end

  def changeset(%__MODULE__{} = component, params) do
    component
    |> cast(set_value_params(params), [])
    |> cast_embed(:interpretation)
    |> cast_embed(:code, required: true)
    |> cast_embed(:value, required: true)
    |> cast_embed(:reference_ranges)
  end

  def set_value_params(params) do
    if Map.get(params, "value") do
      params
    else
      Map.merge(params, %{"value" => Map.take(params, ~w(
          value_string
          value_time
          value_boolean
          value_date_time
          value_quantity
          value_codeable_concept
          value_sampled_data
          value_range
          value_ratio
          value_period
      ))})
    end
  end
end
