defmodule Core.ServiceRequest do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.Reference
  alias Core.ServiceRequests.Occurrence
  alias Core.StatusHistory

  @status_active "active"
  @status_in_progress "in_progress"
  @status_completed "completed"
  @status_entered_in_error "entered_in_error"
  @status_cancelled "cancelled"

  @intent_order "order"
  @intent_plan "plan"

  @laboratory_procedure "108252007"
  @counselling "409063005"

  def status(:active), do: @status_active
  def status(:in_progress), do: @status_in_progress
  def status(:completed), do: @status_completed
  def status(:entered_in_error), do: @status_entered_in_error
  def status(:cancelled), do: @status_cancelled

  def intent(:order), do: @intent_order
  def intent(:plan), do: @intent_plan

  def category(:laboratory_procedure), do: @laboratory_procedure
  def category(:counselling), do: @counselling

  @primary_key :_id
  schema :service_requests do
    field(:_id, presence: true, mongo_uuid: true)
    field(:status, presence: true)
    field(:status_reason, reference: [path: "status_reason"])
    field(:explanatory_letter)
    field(:status_history)
    field(:intent, presence: true)
    field(:category, dictionary_reference: [path: "category", referenced_field: "system", field: "code"])
    field(:code, dictionary_reference: [path: "code", referenced_field: "system", field: "code"])
    field(:subject, presence: true)
    field(:context, reference: [path: "context"])
    field(:occurrence, reference: [path: "occurrence"])
    field(:authored_on, presence: true, reference: [path: "authored_on"])
    field(:requester_employee, presence: true, reference: [path: "requester_employee"])
    field(:requester_legal_entity, presence: true, reference: [path: "requester_legal_entity"])
    field(:priority)

    field(:performer_type,
      reference: [path: "performer_type"],
      dictionary_reference: [referenced_field: "system", field: "code"]
    )

    field(:reason_reference, reference: [path: "reason_reference"])
    field(:supporting_info, reference: [path: "supporting_info"])
    field(:note)
    field(:patient_instruction)
    field(:expiration_date)
    field(:permitted_resources, reference: [path: "permitted_resources"])
    field(:used_by_employee, reference: [path: "used_by_employee"])
    field(:used_by_legal_entity, reference: [path: "used_by_legal_entity"])
    field(:assignee, reference: [path: "assignee"])
    field(:signed_content_links)
    field(:requisition, presence: true)
    field(:status_history)
    field(:completed_with, reference: [path: "completed_with"])

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"id", v} ->
          {:_id, v}

        {"category", v} ->
          {:category, CodeableConcept.create(v)}

        {"code", v} ->
          {:code, CodeableConcept.create(v)}

        {"requester_employee", v} ->
          {:requester_employee, Reference.create(v)}

        {"requester_legal_entity", v} ->
          {:requester_legal_entity, Reference.create(v)}

        {"context", v} ->
          {:context, Reference.create(v)}

        {"used_by_employee", nil} ->
          {:used_by_employee, nil}

        {"used_by_employee", v} ->
          {:used_by_employee, Reference.create(v)}

        {"used_by_legal_entity", nil} ->
          {:used_by_legal_entity, nil}

        {"used_by_legal_entity", v} ->
          {:used_by_legal_entity, Reference.create(v)}

        {"performer_type", v} ->
          {:performer_type, CodeableConcept.create(v)}

        {"reason_reference", nil} ->
          {:reason_reference, nil}

        {"reason_reference", v} ->
          {:reason_reference, Enum.map(v, &Reference.create/1)}

        {"supporting_info", nil} ->
          {:supporting_info, nil}

        {"supporting_info", v} ->
          {:supporting_info, Enum.map(v, &Reference.create/1)}

        {"permitted_resources", nil} ->
          {:permitted_resources, nil}

        {"permitted_resources", v} ->
          {:permitted_resources, Enum.map(v, &Reference.create/1)}

        {"occurrence", %{"type" => type, "value" => value}} ->
          {:occurrence, Occurrence.create(type, value)}

        {"occurrence_" <> type, value} ->
          {:occurrence, Occurrence.create(type, value)}

        {"status_reason", nil} ->
          {:status_reason, nil}

        {"status_reason", v} ->
          {:status_reason, CodeableConcept.create(v)}

        {"expiration_date", v} ->
          {:expiration_date, create_datetime(v)}

        {"status_history", nil} ->
          {:status_history, nil}

        {"status_history", v} ->
          {:status_history, Enum.map(v, &StatusHistory.create/1)}

        {"completed_with", nil} ->
          {:completed_with, nil}

        {"completed_with", v} ->
          {:completed_with, Reference.create(v)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
