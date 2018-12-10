defmodule Core.Condition do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.Evidence
  alias Core.Maybe
  alias Core.Reference
  alias Core.Source
  alias Core.Stage

  @primary_key :_id
  schema :conditions do
    field(:_id, presence: true, mongo_uuid: true)
    field(:clinical_status)
    field(:verification_status)
    field(:severity, reference: [path: "severity"], dictionary_reference: [referenced_field: "system", field: "code"])
    field(:code, dictionary_reference: [path: "code", referenced_field: "system", field: "code"])
    field(:body_sites, dictionary_reference: [path: "body_sites", referenced_field: "system", field: "code"])
    field(:patient_id, presence: true)
    field(:context, presence: true, reference: [path: "context"])
    field(:onset_date, reference: [path: "onset_date"])
    field(:primary_source, strict_presence: true)
    field(:source, presence: true, reference: [path: "source"])
    field(:asserted_date)
    field(:stage, reference: [path: "stage"])
    field(:evidences, reference: [path: "evidences"])

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"evidences", nil} ->
          {:evidences, nil}

        {"evidences", v} ->
          {:evidences, Enum.map(v, &Evidence.create/1)}

        {"stage", v} ->
          {:stage, Maybe.map(v, &Stage.create/1)}

        {"onset_date", v} ->
          {:onset_date, Maybe.map(v, &create_datetime/1)}

        {"body_sites", nil} ->
          {:body_sites, nil}

        {"body_sites", v} ->
          {:body_sites, Enum.map(v, &CodeableConcept.create/1)}

        {"severity", v} ->
          {:severity, Maybe.map(v, &CodeableConcept.create/1)}

        {"context", v} ->
          {:context, Reference.create(v)}

        {"code", v} ->
          {:code, CodeableConcept.create(v)}

        {"source", %{"type" => type, "value" => value}} ->
          {:source, Source.create(type, value)}

        {"asserted_date", v} ->
          {:asserted_date, Maybe.map(v, &create_datetime/1)}

        {"report_origin", v} ->
          {:source, %Source{type: "report_origin", value: CodeableConcept.create(v)}}

        {"asserter", v} ->
          {:source, %Source{type: "asserter", value: Reference.create(v)}}

        {"id", v} ->
          {:_id, v}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
