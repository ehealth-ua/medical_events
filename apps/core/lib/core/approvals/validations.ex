defmodule Core.Approvals.Validations do
  @moduledoc false

  import Core.Schema, only: [add_validations: 3]

  alias Core.Approval

  def validate_granted_to(%Approval{granted_to: granted_to} = approval, user_id, client_id) do
    identifier =
      add_validations(
        granted_to.identifier,
        :value,
        employee: [
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee is not an active doctor",
            status: "Employee is not an active doctor",
            legal_entity_id: "Employee #{granted_to.identifier.value} doesn't belong to your legal entity"
          ]
        ],
        approval_granted_to_reference: [client_id: client_id, user_id: user_id]
      )

    %{approval | granted_to: %{granted_to | identifier: identifier}}
  end

  def validate_granted_resources(%Approval{granted_resources: granted_resources} = approval, patient_id_hash) do
    granted_resources =
      Enum.map(granted_resources, fn resource ->
        reference_type = resource.identifier.type.coding |> List.first() |> Map.get(:code)

        identifier =
          case reference_type do
            "episode_of_care" ->
              add_validations(
                resource.identifier,
                :value,
                episode_reference: [patient_id_hash: patient_id_hash]
              )

            "diagnostic_report" ->
              add_validations(resource.identifier, :value,
                diagnostic_report_reference: [patient_id_hash: patient_id_hash]
              )
          end

        %{resource | identifier: identifier}
      end)

    %{approval | granted_resources: granted_resources}
  end

  def validate_patient(%Approval{patient_id: patient_id_hash}, patient_id_hash), do: :ok
  def validate_patient(_, _), do: {:error, {:access_denied, "Access denied - request to other patient's approval"}}
end
