defmodule Core.Conditions.Validations do
  @moduledoc false

  alias Core.Condition
  alias Core.Reference
  alias Core.Source
  import Core.Schema, only: [add_validations: 3]

  def validate_onset_date(%Condition{} = condition) do
    now = DateTime.utc_now()

    add_validations(
      condition,
      :onset_date,
      datetime: [less_than_or_equal_to: now, message: "Onset date must be in past"]
    )
  end

  def validate_context(%Condition{context: context} = condition, encounter_id) do
    identifier = add_validations(context.identifier, :value, value: [equals: encounter_id])
    %{condition | context: %{context | identifier: identifier}}
  end

  def validate_source(%Condition{source: %Source{type: "asserter"}} = condition, client_id) do
    condition =
      add_validations(
        condition,
        :source,
        source: [primary_source: condition.primary_source, primary_required: "asserter"]
      )

    source = condition.source
    source = %{source | value: validate_asserter(source.value, client_id)}
    %{condition | source: source}
  end

  def validate_source(%Condition{} = condition, _) do
    add_validations(condition, :source, source: [primary_source: condition.primary_source])
  end

  def validate_asserter(%Reference{} = asserter, client_id) do
    identifier =
      add_validations(
        asserter.identifier,
        :value,
        employee: [
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee is not an active doctor",
            status: "Employee is not an active doctor"
          ]
        ]
      )

    %{asserter | identifier: identifier}
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
                observation_reference: [patient_id: patient_id, observations: observations]
              )

            %{detail | identifier: identifier}
          end)

        %{evidence | details: details}
      end)

    %{condition | evidences: evidences}
  end
end
