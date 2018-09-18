defmodule Core.Patients.AllergyIntolerances.Validations do
  @moduledoc false

  alias Core.AllergyIntolerance
  alias Core.Reference
  alias Core.Source
  import Core.Schema, only: [add_validations: 3]

  def validate_context(%AllergyIntolerance{context: context} = allergy_intolerance, encounter_id) do
    identifier = add_validations(context.identifier, :value, value: [equals: encounter_id])
    %{allergy_intolerance | context: %{context | identifier: identifier}}
  end

  def validate_source(%AllergyIntolerance{id: id, source: %Source{type: "asserter"}} = allergy_intolerance, client_id) do
    allergy_intolerance =
      add_validations(
        allergy_intolerance,
        :source,
        source: [primary_source: allergy_intolerance.primary_source, primary_required: "asserter"]
      )

    source = allergy_intolerance.source
    source = %{source | value: validate_asserter(id, source.value, client_id)}
    %{allergy_intolerance | source: source}
  end

  def validate_source(%AllergyIntolerance{} = allergy_intolerance, _) do
    add_validations(allergy_intolerance, :source, source: [primary_source: allergy_intolerance.primary_source])
  end

  def validate_asserter(id, %Reference{} = asserter, client_id) do
    identifier =
      add_validations(
        asserter.identifier,
        :value,
        employee: [legal_entity_id: client_id, ets_key: "allergy_intolerance_#{id}_asserter_employee"]
      )

    %{asserter | identifier: identifier}
  end

  def validate_onset_date_time(%AllergyIntolerance{} = allergy_intolerance) do
    validate_date(allergy_intolerance, :onset_date_time, "Onset date time must be in past")
  end

  def validate_asserted_date(%AllergyIntolerance{} = allergy_intolerance) do
    validate_date(allergy_intolerance, :asserted_date, "Asserted date must be in past")
  end

  def validate_last_occurence(%AllergyIntolerance{} = allergy_intolerance) do
    validate_date(allergy_intolerance, :last_occurrence, "Last occurrence must be in past")
  end

  defp validate_date(%AllergyIntolerance{} = allergy_intolerance, field, message) do
    now = DateTime.utc_now()

    add_validations(
      allergy_intolerance,
      field,
      datetime: [less_than_or_equal_to: now, message: message]
    )
  end
end
