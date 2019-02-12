defmodule Core.ServiceRequest do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.Reference
  alias Core.ServiceRequests.Occurrence
  alias Core.StatusHistory

  @status_active "active"
  @status_completed "completed"
  @status_entered_in_error "entered_in_error"
  @status_cancelled "cancelled"

  @intent_order "order"
  @intent_plan "plan"

  def status(:active), do: @status_active
  def status(:completed), do: @status_completed
  def status(:entered_in_error), do: @status_entered_in_error
  def status(:cancelled), do: @status_cancelled

  def intent(:order), do: @intent_order
  def intent(:plan), do: @intent_plan

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
    field(:requester, presence: true, reference: [path: "requester"])
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
    field(:permitted_episodes, reference: [path: "permitted_episodes"])
    field(:used_by, reference: [path: "used_by"])
    field(:assignee, reference: [path: "assignee"])
    field(:signed_content_links)
    field(:requisition, presence: true)
    field(:status_history)

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

        {"requester", v} ->
          {:requester, Reference.create(v)}

        {"context", v} ->
          {:context, Reference.create(v)}

        {"used_by", nil} ->
          {:used_by, nil}

        {"used_by", v} ->
          {:used_by, Reference.create(v)}

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

        {"permitted_episodes", nil} ->
          {:permitted_episodes, nil}

        {"permitted_episodes", v} ->
          {:permitted_episodes, Enum.map(v, &Reference.create/1)}

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

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
