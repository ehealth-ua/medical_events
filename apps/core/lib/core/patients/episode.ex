defmodule Core.Episode do
  @moduledoc false

  use Core.Schema
  alias Core.CodeableConcept
  alias Core.Coding
  alias Core.DatePeriod
  alias Core.DiagnosesHistory
  alias Core.Diagnosis
  alias Core.Reference
  alias Core.StatusHistory

  @status_active "active"
  @status_closed "closed"
  @status_cancelled "entered_in_error"

  def status(:active), do: @status_active
  def status(:closed), do: @status_closed
  def status(:cancelled), do: @status_cancelled

  embedded_schema do
    field(:id, presence: true, mongo_uuid: true)
    field(:name)
    field(:status)

    field(:status_reason,
      reference: [path: "status_reason"],
      dictionary_reference: [referenced_field: "system", field: "code"]
    )

    field(:closing_summary)
    field(:explanatory_letter)
    field(:status_history)
    field(:current_diagnoses)
    field(:type, presence: true, dictionary_reference: [referenced_field: "system", field: "code"])
    field(:diagnoses_history)
    field(:managing_organization, presence: true, reference: [path: "managing_organization"])
    field(:period, presence: true, reference: [path: "period"])
    field(:care_manager, presence: true, reference: [path: "care_manager"])

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"type", v} ->
          {:type, Coding.create(v)}

        {"managing_organization", v} ->
          {:managing_organization, Reference.create(v)}

        {"period", v} ->
          {:period, DatePeriod.create(v)}

        {"care_manager", v} ->
          {:care_manager, Reference.create(v)}

        {"status_reason", nil} ->
          {:status_reason, nil}

        {"status_reason", v} ->
          {:status_reason, CodeableConcept.create(v)}

        {"status_history", nil} ->
          {:status_history, nil}

        {"status_history", v} ->
          {:status_history, Enum.map(v, &StatusHistory.create/1)}

        {"diagnoses_history", nil} ->
          {:diagnoses_history, nil}

        {"diagnoses_history", v} ->
          {:diagnoses_history, Enum.map(v, &DiagnosesHistory.create/1)}

        {"current_diagnoses", nil} ->
          {:current_diagnoses, nil}

        {"current_diagnoses", v} ->
          {:current_diagnoses, Enum.map(v, &Diagnosis.create/1)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
