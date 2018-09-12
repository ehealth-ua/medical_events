defmodule Core.Observation do
  @moduledoc false

  use Core.Schema
  alias Core.CodeableConcept
  alias Core.Observations.Component
  alias Core.Observations.EffectiveAt
  alias Core.Observations.ReferenceRange
  alias Core.Observations.Value
  alias Core.Observations.Values.Quantity
  alias Core.Observations.Values.Range
  alias Core.Observations.Values.Ratio
  alias Core.Observations.Values.SampledData
  alias Core.Period
  alias Core.Reference
  alias Core.Source

  @status_valid "valid"
  @status_entered_in_error "entered_in_error"

  def status(:valid), do: @status_valid
  def status(:entered_in_error), do: @status_entered_in_error

  @primary_key :_id
  schema :observations do
    field(:_id, presence: true)
    field(:based_on)
    field(:status, presence: true)
    field(:categories, presence: true, reference: [path: "categories"])
    field(:code, presence: true, reference: [path: "code"])
    field(:patient_id, presence: true)
    field(:context, presence: true, reference: [path: "context"])
    field(:effective_at, presence: true, reference: [path: "effective_at"])
    field(:issued, presence: true)
    field(:primary_source, strict_presence: true)
    field(:source, presence: true, reference: [path: "source"])
    field(:value, presence: true)
    field(:interpretation, reference: [path: "interpretation"])
    field(:comment)
    field(:body_site, reference: [path: "body_site"])
    field(:method, reference: [path: "method"])
    field(:reference_ranges, reference: [path: "reference_ranges"])
    field(:components, reference: [path: "components"])

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"categories", v} ->
          {:categories, Enum.map(v, &CodeableConcept.create/1)}

        {"context", v} ->
          {:context, Reference.create(v)}

        {"effective_date_time", v} ->
          {:ok, datetime, _} = DateTime.from_iso8601(v)
          {:effective_at, %EffectiveAt{type: "effective_date_time", value: datetime}}

        {"effective_period", v} ->
          {:effective_at, %EffectiveAt{type: "effective_period", value: Period.create(v)}}

        {"issued", v} ->
          {:ok, datetime, _} = DateTime.from_iso8601(v)
          {:issued, datetime}

        {"report_origin", v} ->
          {:source, %Source{type: "report_origin", value: CodeableConcept.create(v)}}

        {"performer", v} ->
          {:source, %Source{type: "performer", value: Reference.create(v)}}

        {"code", v} ->
          {:code, CodeableConcept.create(v)}

        {"id", v} ->
          {:_id, v}

        {"interpretation", v} ->
          {:interpretation, CodeableConcept.create(v)}

        {"body_site", v} ->
          {:body_site, CodeableConcept.create(v)}

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

        {"components", v} ->
          {:components, Enum.map(v, &Component.create/1)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
