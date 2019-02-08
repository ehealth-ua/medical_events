defmodule Core.Patients.MedicationStatements.Validations do
  @moduledoc false

  import Core.Schema, only: [add_validations: 3]

  alias Core.MedicationStatement
  alias Core.Reference
  alias Core.Source

  def validate_asserted_date(%MedicationStatement{} = medication_statement) do
    now = DateTime.utc_now()
    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:medication_statement_max_days_passed]

    add_validations(medication_statement, :asserted_date,
      datetime: [less_than_or_equal_to: now, message: "Asserted date must be in past"],
      max_days_passed: [max_days_passed: max_days_passed]
    )
  end

  def validate_context(%MedicationStatement{context: context} = medication_statement, encounter_id) do
    identifier =
      add_validations(context.identifier, :value,
        value: [equals: encounter_id, message: "Submitted context is not allowed for the medication statement"]
      )

    %{medication_statement | context: %{context | identifier: identifier}}
  end

  def validate_source(%MedicationStatement{source: %Source{type: "asserter"}} = medication_statement, client_id) do
    medication_statement =
      add_validations(
        medication_statement,
        :source,
        source: [primary_source: medication_statement.primary_source, primary_required: "asserter"]
      )

    source = medication_statement.source
    source = %{source | value: validate_asserter(source.value, client_id)}
    %{medication_statement | source: source}
  end

  def validate_source(%MedicationStatement{} = medication_statement, _) do
    add_validations(medication_statement, :source, source: [primary_source: medication_statement.primary_source])
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
            status: "Employee is not an active doctor",
            legal_entity_id: "Employee #{asserter.identifier.value} doesn't belong to your legal entity"
          ]
        ]
      )

    %{asserter | identifier: identifier}
  end

  def validate_based_on(%MedicationStatement{based_on: nil} = medication_statement, _), do: medication_statement

  def validate_based_on(%MedicationStatement{based_on: based_on} = medication_statement, patient_id_hash) do
    identifier =
      add_validations(based_on.identifier, :value, medication_request_reference: [patient_id_hash: patient_id_hash])

    %{medication_statement | based_on: %{based_on | identifier: identifier}}
  end
end
