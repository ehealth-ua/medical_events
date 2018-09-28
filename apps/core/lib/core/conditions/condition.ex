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
    field(:severity, reference: [path: "severity"])
    field(:code, reference: [path: "code"])
    field(:body_sites, reference: [path: "body_sites"])
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
        {"evidences", v} ->
          {:evidences, Maybe.map_list(v, &Evidence.create/1)}

        {"stage", v} ->
          {:stage, Maybe.map(v, &Stage.create/1)}

        {"onset_date", v} ->
          {:onset_date, Maybe.map(v, &create_date/1)}

        {"body_sites", v} ->
          {:body_sites, Maybe.map_list(v, &CodeableConcept.create/1)}

        {"severity", v} ->
          {:severity, Maybe.map(v, &CodeableConcept.create/1)}

        {"context", v} ->
          {:context, Reference.create(v)}

        {"code", v} ->
          {:code, CodeableConcept.create(v)}

        {"source", %{"type" => type, "value" => value}} ->
          {:source, Source.create(type, value)}

        {"asserted_date", v} ->
          {:asserted_date, Maybe.map(v, &create_date/1)}

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

  defp create_date(%DateTime{} = date), do: date

  defp create_date(date) when is_binary(date) do
    erl_date =
      date
      |> Date.from_iso8601!()
      |> Date.to_erl()

    {erl_date, {0, 0, 0}}
    |> NaiveDateTime.from_erl!()
    |> DateTime.from_naive!("Etc/UTC")
  end
end
