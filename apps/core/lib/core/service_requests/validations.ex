defmodule Core.ServiceRequests.Validations do
  @moduledoc false

  import Core.Schema, only: [add_validations: 3]

  alias Core.Microservices.DigitalSignature
  alias Core.ServiceRequest
  alias Core.ServiceRequests.Occurrence

  def validate_signatures(%ServiceRequest{} = service_request, %{"drfo" => drfo}, user_id, client_id) do
    if DigitalSignature.config()[:enabled] do
      requester = service_request.requester

      identifier =
        add_validations(
          requester.identifier,
          :value,
          drfo: [drfo: drfo, client_id: client_id, user_id: user_id]
        )

      %{service_request | requester: %{requester | identifier: identifier}}
    else
      service_request
    end
  end

  def validate_context(%ServiceRequest{} = service_request, patient_id_hash) do
    context = service_request.context

    identifier =
      add_validations(
        context.identifier,
        :value,
        encounter_reference: [patient_id_hash: patient_id_hash]
      )

    %{service_request | context: %{context | identifier: identifier}}
  end

  def validate_occurrence(%ServiceRequest{occurrence: %Occurrence{type: "date_time"} = occurrence} = service_request) do
    now = DateTime.utc_now()

    occurrence =
      add_validations(
        occurrence,
        :value,
        datetime: [greater_than: now, message: "Occurrence date must be in the future"]
      )

    %{service_request | occurrence: occurrence}
  end

  def validate_occurrence(%ServiceRequest{occurrence: %Occurrence{type: "period"} = occurrence} = service_request) do
    now = DateTime.utc_now()

    occurrence =
      occurrence.value
      |> add_validations(
        :start,
        datetime: [greater_than: now, message: "Occurrence start date must be in the future"]
      )
      |> add_validations(
        :end,
        datetime: [
          greater_than: occurrence.value.start,
          message: "Occurrence end date must be greater than the start date"
        ]
      )

    %{service_request | occurrence: occurrence}
  end

  def validate_occurrence(service_request), do: service_request

  def validate_authored_on(%ServiceRequest{} = service_request) do
    add_validations(service_request, :authored_on, datetime: [less_than: DateTime.utc_now()])
  end

  def validate_supporting_info(%ServiceRequest{} = service_request, patient_id_hash) do
    supporting_info =
      Enum.map(service_request.supporting_info, fn info ->
        identifier = add_validations(info.identifier, :value, episode_reference: [patient_id_hash: patient_id_hash])
        %{info | identifier: identifier}
      end)

    %{service_request | supporting_info: supporting_info}
  end

  def validate_reason_reference(%ServiceRequest{} = service_request, patient_id_hash) do
    reason_references = service_request.reason_reference || []

    references =
      Enum.map(reason_references, fn reference ->
        identifier = reference.identifier
        reference_type = identifier.type.coding |> List.first() |> Map.get(:code)

        case reference_type do
          "observation" ->
            add_validations(identifier, :value, observation_reference: [patient_id_hash: patient_id_hash])

          "condition" ->
            add_validations(identifier, :value, condition_reference: [patient_id_hash: patient_id_hash])
        end
      end)

    %{service_request | reason_reference: references}
  end

  def validate_permitted_episodes(%ServiceRequest{} = service_request, patient_id_hash) do
    episodes = service_request.permitted_episodes || []

    references =
      Enum.map(episodes, fn reference ->
        identifier =
          add_validations(reference.identifier, :value, episode_reference: [patient_id_hash: patient_id_hash])

        %{reference | identifier: identifier}
      end)

    %{service_request | permitted_episodes: references}
  end

  def validate_used_by(%ServiceRequest{} = service_request, client_id) do
    used_by = service_request.used_by

    identifier =
      add_validations(used_by.identifier, :value,
        employee: [
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            status: "Employee is not approved",
            legal_entity_id: "Employee #{used_by.identifier.value} doesn't belong to your legal entity"
          ]
        ]
      )

    %{service_request | used_by: %{used_by | identifier: identifier}}
  end
end
