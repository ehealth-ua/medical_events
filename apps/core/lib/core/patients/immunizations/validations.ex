defmodule Core.Patients.Immunizations.Validations do
  @moduledoc false

  import Core.Schema, only: [add_validations: 3]

  alias Core.Immunization
  alias Core.Reference
  alias Core.Source
  alias Core.Validators.Date, as: DateValidator

  def validate_date(%Immunization{} = immunization) do
    now = DateTime.utc_now()
    add_validations(immunization, :date, datetime: [less_than_or_equal_to: now, message: "Date must be in past"])

    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:immunization_max_days_passed]

    add_validations(immunization, :date, by: &DateValidator.validate_expiration(&1, max_days_passed))
  end

  def validate_context(%Immunization{context: context} = immunization, encounter_id) do
    identifier = add_validations(context.identifier, :value, value: [equals: encounter_id])
    %{immunization | context: %{context | identifier: identifier}}
  end

  def validate_source(%Immunization{source: %Source{type: "performer"}} = immunization, client_id) do
    immunization =
      add_validations(
        immunization,
        :source,
        source: [primary_source: immunization.primary_source, primary_required: "performer"]
      )

    source = immunization.source
    source = %{source | value: validate_performer(source.value, client_id)}
    %{immunization | source: source}
  end

  def validate_source(%Immunization{} = immunization, _) do
    add_validations(immunization, :source, source: [primary_source: immunization.primary_source])
  end

  def validate_performer(%Reference{} = performer, client_id) do
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
            status: "Employee is not an active doctor"
          ]
        ]
      )

    %{performer | identifier: identifier}
  end

  def validate_reactions(%Immunization{} = immunization, observations, patient_id) do
    reactions = immunization.reactions || []

    reactions =
      Enum.map(reactions, fn reaction ->
        detail = reaction.detail

        identifier =
          add_validations(
            detail.identifier,
            :value,
            observation_reference: [patient_id: patient_id, observations: observations]
          )

        %{reaction | detail: %{detail | identifier: identifier}}
      end)

    # todo: make default values for list fields as empty arrays
    if reactions == [] do
      %{immunization | reactions: nil}
    else
      %{immunization | reactions: reactions}
    end
  end
end
