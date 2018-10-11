defmodule Core.Patients.Encounters.Validations do
  @moduledoc false

  import Core.Schema, only: [add_validations: 3]

  alias Core.Encounter
  alias Core.Headers
  alias Core.Validators.Date, as: DateValidator
  alias Core.Validators.Signature

  @il_microservice Application.get_env(:core, :microservices)[:il]

  def validate_episode(%Encounter{episode: episode} = encounter, patient_id_hash) do
    identifier =
      add_validations(
        episode.identifier,
        :value,
        episode_context: [patient_id_hash: patient_id_hash]
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
            legal_entity_id: "User can create an episode only for the doctor that works for the same legal_entity"
          ]
        ]
      )

    %{encounter | performer: %{performer | identifier: identifier}}
  end

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

  def validate_diagnoses(%Encounter{} = encounter, conditions, patient_id_hash) do
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
      diagnoses_role: [type: "chief_complaint", message: "Encounter must have at least one chief complaint"]
    )
  end

  def validate_date(%Encounter{} = encounter) do
    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:encounter_max_days_passed]

    add_validations(encounter, :date, by: &DateValidator.validate_expiration(&1, max_days_passed))
  end

  def validate_signatures(signer, employee_id, user_id, client_id) do
    if Confex.fetch_env!(:core, :digital_signarure_enabled?) do
      do_validate_signatures(signer, employee_id, user_id, client_id)
    else
      :ok
    end
  end

  defp do_validate_signatures(%{"drfo" => drfo}, employee_id, user_id, client_id) do
    headers = [Headers.create(:user_id, user_id), Headers.create(:client_id, client_id)]

    with {:ok, %{"data" => %{"party" => party}}} <- @il_microservice.get_employee_users(employee_id, headers),
         :ok <- Signature.validate_drfo(drfo, party["tax_id"]),
         :ok <- validate_performer_is_current_user(party["users"], user_id) do
      :ok
    end
  end

  defp do_validate_signatures(_, _, _, _), do: {:error, "Invalid drfo"}

  defp validate_performer_is_current_user(users, user_id) do
    users
    |> Enum.any?(&(&1["user_id"] == user_id))
    |> case do
      true -> :ok
      _ -> {:error, "Employee is not performer of encouner"}
    end
  end
end
