defmodule Core.Patients.RiskAssessments.Validations do
  @moduledoc false

  import Core.Schema, only: [add_validations: 3]

  alias Core.Patients.RiskAssessments.ExtendedReference
  alias Core.Patients.RiskAssessments.Prediction
  alias Core.Patients.RiskAssessments.Reason
  alias Core.Patients.RiskAssessments.When
  alias Core.Period
  alias Core.Reference
  alias Core.RiskAssessment

  def validate_asserted_date(%RiskAssessment{} = risk_assessment) do
    now = DateTime.utc_now()
    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:risk_assessment_max_days_passed]

    add_validations(risk_assessment, :asserted_date,
      datetime: [less_than_or_equal_to: now, message: "Asserted date must be in past"],
      max_days_passed: [max_days_passed: max_days_passed]
    )
  end

  def validate_context(%RiskAssessment{context: context} = risk_assessment, encounter_id) do
    identifier =
      add_validations(context.identifier, :value,
        value: [equals: encounter_id, message: "Submitted context is not allowed for the risk_assessments"]
      )

    %{risk_assessment | context: %{context | identifier: identifier}}
  end

  def validate_reason_reference(
        %RiskAssessment{reason: %Reason{type: "reason_reference"} = reason} = risk_assessment,
        observations,
        conditions,
        patient_id_hash
      ) do
    reference_type = reason.reference.identifier.type.coding |> List.first() |> Map.get(:code)

    identifier = reason.reference.identifier

    # TODO: add diagnostic_report_reference validation when diagnostic_report is implemented
    identifier =
      case reference_type do
        "observation" ->
          add_validations(identifier, :value,
            observation_context: [patient_id_hash: patient_id_hash, observations: observations]
          )

        "condition" ->
          add_validations(identifier, :value,
            condition_context: [patient_id_hash: patient_id_hash, conditions: conditions]
          )
      end

    %{risk_assessment | reason: %{reason | reference: %{reason.reference | identifier: identifier}}}
  end

  def validate_reason_reference(%RiskAssessment{} = risk_assessment, _, _, _), do: risk_assessment

  def validate_basis_references(%RiskAssessment{basis: nil} = risk_assessment, _, _, _), do: risk_assessment

  def validate_basis_references(%RiskAssessment{basis: %ExtendedReference{references: nil}} = risk_assessment, _, _, _),
    do: risk_assessment

  def validate_basis_references(
        %RiskAssessment{basis: %ExtendedReference{references: references} = basis} = risk_assessment,
        observations,
        conditions,
        patient_id_hash
      ) do
    references =
      Enum.map(references, fn reference ->
        validate_basis_reference(reference, observations, conditions, patient_id_hash)
      end)

    %{risk_assessment | basis: %{basis | references: references}}
  end

  def validate_basis_reference(%Reference{} = reference, observations, conditions, patient_id_hash) do
    reference_type = reference.identifier.type.coding |> List.first() |> Map.get(:code)

    # TODO: add diagnostic_report_reference validation when diagnostic_report is implemented
    identifier =
      case reference_type do
        "observation" ->
          add_validations(reference.identifier, :value,
            observation_context: [patient_id_hash: patient_id_hash, observations: observations]
          )

        "condition" ->
          add_validations(reference.identifier, :value,
            condition_context: [patient_id_hash: patient_id_hash, conditions: conditions]
          )
      end

    %{reference | identifier: identifier}
  end

  def validate_performer(%RiskAssessment{performer: %Reference{} = performer} = risk_assessment, client_id) do
    identifier =
      add_validations(
        performer.identifier,
        :value,
        employee: [
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee is not an active doctor",
            status: "Employee is not an active doctor",
            legal_entity_id: "Employee #{performer.identifier.value} doesn't belong to your legal entity"
          ]
        ]
      )

    %{risk_assessment | performer: %{performer | identifier: identifier}}
  end

  def validate_performer(%RiskAssessment{} = risk_assessment, _), do: risk_assessment

  def validate_predictions(%RiskAssessment{predictions: nil} = risk_assessment), do: risk_assessment

  def validate_predictions(%RiskAssessment{predictions: predictions} = risk_assessment) do
    predictions = Enum.map(predictions, fn prediction -> validate_when_period(prediction) end)

    %{risk_assessment | predictions: predictions}
  end

  def validate_when_period(%Prediction{when: %When{type: "when_period"}} = prediction) do
    when_period = %{prediction.when | value: validate_period(prediction.when.value)}
    %{prediction | when: when_period}
  end

  def validate_when_period(%Prediction{} = prediction), do: prediction

  defp validate_period(%Period{} = period) do
    now = DateTime.utc_now()

    period =
      add_validations(
        period,
        :start,
        datetime: [less_than_or_equal_to: now, message: "Start date must be in past"]
      )

    if period.end do
      add_validations(
        period,
        :end,
        datetime: [less_than_or_equal_to: now, message: "End date must be in past"],
        datetime: [greater_than: period.start, message: "End date must be greater than the start date"]
      )
    else
      period
    end
  end
end
