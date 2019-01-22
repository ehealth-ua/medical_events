defmodule Core.Patients.Encounters.Validations do
  @moduledoc false

  import Core.Schema, only: [add_validations: 3]

  alias Core.Coding
  alias Core.Encounter
  alias Core.Headers
  alias Core.Microservices.DigitalSignature
  alias Core.Validators.Signature

  @il_microservice Application.get_env(:core, :microservices)[:il]

  def validate_episode(%Encounter{episode: episode} = encounter, client_id, patient_id_hash) do
    identifier =
      add_validations(
        episode.identifier,
        :value,
        episode_context: [client_id: client_id, patient_id_hash: patient_id_hash]
      )

    %{encounter | episode: %{episode | identifier: identifier}}
  end

  def validate_visit(%Encounter{visit: visit} = encounter, current_visit, patient_id_hash) do
    identifier =
      add_validations(
        visit.identifier,
        :value,
        visit_context: [visit: current_visit, patient_id_hash: patient_id_hash]
      )

    %{encounter | visit: %{visit | identifier: identifier}}
  end

  def validate_performer(%Encounter{} = encounter, client_id) do
    performer = encounter.performer

    identifier =
      performer.identifier
      |> add_validations(
        :value,
        employee: [
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee submitted as a care_manager is not a doctor",
            status: "Doctor submitted as a care_manager is not active",
            legal_entity_id: "Employee #{performer.identifier.value} doesn't belong to your legal entity"
          ]
        ]
      )

    %{encounter | performer: %{performer | identifier: identifier}}
  end

  def validate_division(%Encounter{division: nil} = encounter, _), do: encounter

  def validate_division(%Encounter{} = encounter, client_id) do
    division = encounter.division

    identifier =
      division.identifier
      |> add_validations(
        :value,
        division: [
          status: "ACTIVE",
          legal_entity_id: client_id,
          messages: [
            status: "Division is not active",
            legal_entity_id: "User is not allowed to create encouners for this division"
          ]
        ]
      )

    %{encounter | division: %{division | identifier: identifier}}
  end

  def validate_diagnoses(%Encounter{} = encounter, conditions, %Coding{} = class, patient_id_hash) do
    diagnoses = encounter.diagnoses

    diagnoses =
      Enum.map(diagnoses, fn diagnosis ->
        condition = diagnosis.condition

        identifier =
          add_validations(
            condition.identifier,
            :value,
            diagnosis_condition: [conditions: conditions, patient_id_hash: patient_id_hash]
          )

        %{diagnosis | condition: %{condition | identifier: identifier}}
      end)

    %{encounter | diagnoses: diagnoses}
    |> add_validations(
      :diagnoses,
      diagnoses_role: [type: "primary", message: "Encounter must have at least one chief complaint"],
      diagnoses_code: [code: class.code]
    )
  end

  def validate_incoming_referrals(%Encounter{} = encounter, client_id) do
    incoming_referrals = encounter.incoming_referrals || []

    incoming_referrals =
      Enum.map(incoming_referrals, fn referral ->
        identifier = referral.identifier
        %{referral | identifier: add_validations(identifier, :value, service_request_reference: [client_id: client_id])}
      end)

    %{encounter | incoming_referrals: incoming_referrals}
  end

  def validate_date(%Encounter{} = encounter) do
    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:encounter_max_days_passed]
    now = DateTime.utc_now()

    add_validations(encounter, :date,
      datetime: [less_than_or_equal_to: now, message: "Date must be in past"],
      max_days_passed: [max_days_passed: max_days_passed]
    )
  end

  @spec validate_signatures(map, binary, binary, binary) :: :ok | {:error, term}
  def validate_signatures(signer, employee_id, user_id, client_id) do
    if Confex.fetch_env!(:core, DigitalSignature)[:enabled] do
      do_validate_signatures(signer, employee_id, user_id, client_id)
    else
      :ok
    end
  end

  defp do_validate_signatures(%{"drfo" => drfo}, employee_id, user_id, client_id) when drfo != nil do
    headers = [Headers.create(:user_id, user_id), Headers.create(:client_id, client_id)]
    employee_users_data = @il_microservice.get_employee_users(employee_id, headers)

    with {:ok, %{"data" => %{"party" => party, "legal_entity_id" => legal_entity_id}}} <- employee_users_data,
         :ok <- Signature.validate_drfo(drfo, party["tax_id"]),
         :ok <- validate_performer_client(legal_entity_id, client_id),
         :ok <- validate_performer_is_current_user(party["users"], user_id) do
      :ok
    else
      {:ok, response} -> {:error, response}
      err -> err
    end
  end

  defp do_validate_signatures(_, _, _, _), do: {:error, "Invalid drfo"}

  defp validate_performer_is_current_user(users, user_id) do
    users
    |> Enum.any?(&(&1["user_id"] == user_id))
    |> case do
      true -> :ok
      _ -> {:error, "Employee is not performer of encounter"}
    end
  end

  defp validate_performer_client(client_id, client_id), do: :ok
  defp validate_performer_client(_, _), do: {:error, "Performer does not belong to current legal entity"}
end
