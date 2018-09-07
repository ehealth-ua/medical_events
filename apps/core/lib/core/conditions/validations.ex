defmodule Core.Conditions.Validations do
  @moduledoc false

  alias Core.Condition
  import Core.Schema, only: [add_validations: 3]

  def validate_onset_date(%Condition{} = condition) do
    now = DateTime.utc_now()

    add_validations(
      condition,
      :onset_date,
      date: [less_than_or_equal_to: now, message: "Onset date must be in past"]
    )
  end

  def validate_context(%Condition{context: context} = condition, encounter_id) do
    identifier = add_validations(context.identifier, :value, value: [equals: encounter_id])
    %{condition | context: %{context | identifier: identifier}}
  end

  def validate_evidences(%Condition{evidences: nil} = condition, _, _), do: condition

  def validate_evidences(%Condition{} = condition, observations, patient_id) do
    evidences =
      Enum.map(condition.evidences, fn evidence ->
        details =
          Enum.map(evidence.details, fn detail ->
            identifier =
              add_validations(
                detail.identifier,
                :value,
                evidence_observation: [patient_id: patient_id, observations: observations]
              )

            %{detail | identifier: identifier}
          end)

        %{evidence | details: details}
      end)

    %{condition | evidences: evidences}
  end
end
