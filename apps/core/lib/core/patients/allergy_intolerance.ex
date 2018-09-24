defmodule Core.AllergyIntolerance do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.Reference
  alias Core.Source

  @clinical_status_active "active"
  @clinical_status_inactive "inactive"
  @clinical_status_resolved "resolved"

  @verification_status_confirmed "confirmed"
  @verification_status_refuted "refuted"
  @verification_status_entered_in_error "entered_in_error"

  def clinical_status(:active), do: @clinical_status_active
  def clinical_status(:inactive), do: @clinical_status_inactive
  def clinical_status(:resolved), do: @clinical_status_resolved

  def verification_status(:confirmed), do: @verification_status_confirmed
  def verification_status(:refuted), do: @verification_status_refuted
  def verification_status(:entered_in_error), do: @verification_status_entered_in_error

  embedded_schema do
    field(:id, presence: true, mongo_uuid: true)
    field(:clinical_status, presence: true)
    field(:verification_status, presence: true)
    field(:type, presence: true)
    field(:category, presence: true)
    field(:criticality, presence: true)
    field(:code, presence: true)
    field(:onset_date_time, presence: true)
    field(:asserted_date, presence: true)
    field(:primary_source, strict_presence: true)
    field(:source, presence: true, reference: [path: "source"])
    field(:last_occurrence)
    field(:context, presence: true, reference: [path: "context"])

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"context", v} ->
          {:context, Reference.create(v)}

        {"code", v} ->
          {:code, CodeableConcept.create(v)}

        {"onset_date_time", "" = v} ->
          {:ok, datetime, _} = DateTime.from_iso8601(v)
          {:onset_date_time, datetime}

        {"asserted_date", "" = v} ->
          {:ok, datetime, _} = DateTime.from_iso8601(v)
          {:asserted_date, datetime}

        {"last_occurrence", "" = v} ->
          {:ok, datetime, _} = DateTime.from_iso8601(v)
          {:last_occurrence, datetime}

        {"source", %{"type" => type, "value" => value}} ->
          {:source, Source.create(type, value)}

        {"report_origin", v} ->
          {:source, %Source{type: "report_origin", value: CodeableConcept.create(v)}}

        {"asserter", v} ->
          {:source, %Source{type: "asserter", value: Reference.create(v)}}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
