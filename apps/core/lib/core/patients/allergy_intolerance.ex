defmodule Core.AllergyIntolerance do
  @moduledoc false

  use Core.Schema
  alias Core.CodeableConcept
  alias Core.Reference
  alias Core.Source

  embedded_schema do
    field(:id, presence: true)
    field(:clinical_status, presence: true)
    field(:verification_status, presence: true)
    field(:type, presence: true)
    field(:category, presence: true)
    field(:criticality, presence: true)
    field(:code, presence: true)
    field(:onset_date_time, presence: true)
    field(:asserted_date, presence: true)
    field(:primary_source, strict_presence: true)
    field(:source, presence: true)
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

        {"onset_date_time", v} ->
          {:ok, datetime, _} = DateTime.from_iso8601(v)
          {:onset_date_time, datetime}

        {"asserted_date", v} ->
          {:ok, datetime, _} = DateTime.from_iso8601(v)
          {:asserted_date, datetime}

        {"last_occurrence", v} ->
          {:ok, datetime, _} = DateTime.from_iso8601(v)
          {:last_occurrence, datetime}

        {"report_origin", v} ->
          {:source, %Source{type: "report_origin", value: CodeableConcept.create(v)}}

        {"performer", v} ->
          {:source, %Source{type: "performer", value: Reference.create(v)}}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
