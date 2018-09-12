defmodule Core.Observations.Component do
  @moduledoc false

  use Core.Schema
  alias Core.CodeableConcept
  alias Core.Observations.ReferenceRange
  alias Core.Observations.Value
  alias Core.Observations.Values.Quantity
  alias Core.Observations.Values.Range
  alias Core.Observations.Values.Ratio
  alias Core.Observations.Values.SampledData
  alias Core.Period

  embedded_schema do
    field(:code, presence: true, reference: [path: "code"])
    field(:value, presence: true)
    field(:reference_ranges, reference: [path: "reference_ranges"])
    field(:interpretation, reference: [path: "interpretation"])
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"interpretation", v} ->
          {:interpretation, CodeableConcept.create(v)}

        {"code", v} ->
          {:code, CodeableConcept.create(v)}

        {"value_quantity", v} ->
          {:value, %Value{type: "quantity", value: Quantity.create(v)}}

        {"value_codeable_concept", v} ->
          {:value, %Value{type: "value_codeable_concept", value: CodeableConcept.create(v)}}

        {"value_sampled_data", v} ->
          {:value, %Value{type: "value_sampled_data", value: SampledData.create(v)}}

        {"value_string", v} ->
          {:value, %Value{type: "value_string", value: v}}

        {"value_boolean", v} ->
          {:value, %Value{type: "value_boolean", value: v}}

        {"value_range", v} ->
          {:value, %Value{type: "value_range", value: Range.create(v)}}

        {"value_ratio", v} ->
          {:value, %Value{type: "value_ratio", value: Ratio.create(v)}}

        {"value_time", v} ->
          {:value, %Value{type: "value_time", value: v}}

        {"value_date_time", v} ->
          {:ok, datetime, _} = DateTime.from_iso8601(v)
          {:value, %Value{type: "value_date_time", value: datetime}}

        {"value_period", v} ->
          {:value, %Value{type: "value_period", value: Period.create(v)}}

        {"reference_ranges", v} ->
          {:reference_ranges, Enum.map(v, &ReferenceRange.create/1)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
