defmodule Core.Condition do
  @moduledoc false

  use Core.Schema
  alias Core.CodeableConcept
  alias Core.Evidence
  alias Core.Reference
  alias Core.Source
  alias Core.Stage

  @primary_key :_id
  schema :conditions do
    field(:_id, uuid: true)
    field(:clinical_status)
    field(:verification_status)
    field(:severity, reference: [path: "severity"])
    field(:code, reference: [path: "code"])
    field(:body_sites, reference: [path: "body_sites"])
    field(:patient_id, presence: true)
    field(:context, reference: [path: "context"])
    field(:onset_date, reference: [path: "onset_date"])
    field(:primary_source, strict_presence: true)
    field(:source, presence: true)
    field(:asserted_date)
    field(:asserter)
    field(:stage, reference: [path: "stage"])
    field(:evidences, reference: [path: "evidences"])

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"evidences", v} ->
          {:evidences, Enum.map(v, &Evidence.create/1)}

        {"stage", v} ->
          {:stage, Stage.create(v)}

        {"onset_date", v} ->
          date = v |> Date.from_iso8601!() |> Date.to_erl()
          {:onset_date, {date, {0, 0, 0}} |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")}

        {"body_sites", v} ->
          {:body_sites, Enum.map(v, &CodeableConcept.create/1)}

        {"severity", v} ->
          {:severity, CodeableConcept.create(v)}

        {"context", v} ->
          {:context, Reference.create(v)}

        {"code", v} ->
          {:code, CodeableConcept.create(v)}

        {"asserted_date", v} ->
          date = v |> Date.from_iso8601!() |> Date.to_erl()
          {:asserted_date, {date, {0, 0, 0}} |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")}

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
