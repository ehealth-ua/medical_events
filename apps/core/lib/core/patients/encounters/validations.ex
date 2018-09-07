defmodule Core.Patients.Encounters.Validations do
  @moduledoc false

  alias Core.Encounter
  import Core.Schema, only: [add_validations: 3]

  def validate_episode(%Encounter{episode: episode} = encounter, patient_id) do
    identifier =
      add_validations(
        episode.identifier,
        :value,
        episode_context: [patient_id: patient_id]
      )

    %{encounter | episode: %{episode | identifier: identifier}}
  end

  def validate_visit(%Encounter{visit: visit} = encounter, current_visit, patient_id) do
    identifier =
      add_validations(
        visit.identifier,
        :value,
        visit_context: [visit: current_visit, patient_id: patient_id]
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

  def validate_diagnoses(%Encounter{} = encounter, conditions, patient_id) do
    diagnoses = encounter.diagnoses

    diagnoses =
      Enum.map(diagnoses, fn diagnosis ->
        condition = diagnosis.condition

        identifier =
          add_validations(
            condition.identifier,
            :value,
            diagnosis_condition: [conditions: conditions, patient_id: patient_id]
          )

        %{diagnosis | condition: %{condition | identifier: identifier}}
      end)

    %{encounter | diagnoses: diagnoses}
    |> add_validations(
      :diagnoses,
      diagnoses_role: [type: "chief_complaint", message: "Encounter must have at least one chief complaint"]
    )
  end
end
