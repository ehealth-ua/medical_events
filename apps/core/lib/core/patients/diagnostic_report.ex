defmodule Core.DiagnosticReport do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.EffectiveAt
  alias Core.Executor
  alias Core.Reference
  alias Core.Source

  @status_final "final"
  @status_entered_in_error "entered_in_error"

  def status(:final), do: @status_final
  def status(:entered_in_error), do: @status_entered_in_error

  embedded_schema do
    field(:id, presence: true, mongo_uuid: true)
    field(:based_on, reference: [path: "based_on"])
    field(:origin_episode, reference: [path: "origin_episode"])
    field(:status, presence: true)
    field(:category, dictionary_reference: [path: "category", referenced_field: "system", field: "code"])
    field(:code, presence: true, dictionary_reference: [path: "code", referenced_field: "system", field: "code"])
    field(:encounter, reference: [path: "encounter"])
    field(:effective, reference: [path: "effective"])
    field(:issued, presence: true)
    field(:primary_source, strict_presence: true)
    field(:source, presence: true, reference: [path: "source"])
    field(:recorded_by, presence: true, reference: [path: "recorded_by"])
    field(:results_interpreter, reference: [path: "results_interpreter"])
    field(:managing_organization, reference: [path: "managing_organization"])
    field(:conclusion)
    field(:conclusion_code, dictionary_reference: [path: "conclusion_code", referenced_field: "system", field: "code"])

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"based_on", v} ->
          {:based_on, Reference.create(v)}

        {"origin_episode", nil} ->
          {:origin_episode, nil}

        {"origin_episode", v} ->
          {:origin_episode, Reference.create(v)}

        {"category", nil} ->
          {:category, nil}

        {"category", v} ->
          {:category, Enum.map(v, &CodeableConcept.create/1)}

        {"code", v} ->
          {:code, CodeableConcept.create(v)}

        {"encounter", nil} ->
          {:encounter, nil}

        {"encounter", v} ->
          {:encounter, Reference.create(v)}

        {"effective_date_time", v} ->
          {:effective, EffectiveAt.create("effective_date_time", v)}

        {"effective_period", v} ->
          {:effective, EffectiveAt.create("effective_period", v)}

        {"effective", nil} ->
          {:effective, nil}

        {"effective", %{"type" => type, "value" => value}} ->
          {:effective, EffectiveAt.create(type, value)}

        {"issued", v} ->
          {:issued, create_datetime(v)}

        {"performer", v} ->
          {:source, %Source{type: "performer", value: Executor.create(v)}}

        {"report_origin", v} ->
          {:source, %Source{type: "report_origin", value: CodeableConcept.create(v)}}

        {"source", %{"type" => "performer", "value" => %{"type" => type, "value" => value}}} ->
          {:source, %Source{type: "performer", value: Executor.create(type, value)}}

        {"source", %{"type" => "performer", "value" => v}} ->
          {:source, %Source{type: "performer", value: Executor.create(v)}}

        {"source", %{"type" => type, "value" => value}} ->
          {:source, Source.create(type, value)}

        {"recorded_by", v} ->
          {:recorded_by, Reference.create(v)}

        {"results_interpreter", nil} ->
          {:results_interpreter, nil}

        {"results_interpreter", %{"type" => type, "value" => value}} ->
          {:results_interpreter, Executor.create(type, value)}

        {"results_interpreter", v} ->
          {:results_interpreter, Executor.create(v)}

        {"managing_organization", nil} ->
          {:managing_organization, nil}

        {"managing_organization", v} ->
          {:managing_organization, Reference.create(v)}

        {"conclusion_code", nil} ->
          {:conclusion_code, nil}

        {"conclusion_code", v} ->
          {:conclusion_code, CodeableConcept.create(v)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
