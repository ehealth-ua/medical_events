defmodule Core.Patients.Immunizations.Validations do
  @moduledoc false

  alias Core.Immunization
  alias Core.Reference
  alias Core.Source
  import Core.Schema, only: [add_validations: 3]

  def validate_date(%Immunization{} = immunization) do
    now = DateTime.utc_now()
    add_validations(immunization, :date, datetime: [less_than_or_equal_to: now, message: "Date must be in past"])
  end

  def validate_context(%Immunization{context: context} = immunization, encounter_id) do
    identifier = add_validations(context.identifier, :value, value: [equals: encounter_id])
    %{immunization | context: %{context | identifier: identifier}}
  end

  def validate_source(%Immunization{id: id, source: %Source{type: "performer"}} = immunization, client_id) do
    immunization = add_validations(immunization, :source, source: [primary_source: immunization.primary_source])
    source = immunization.source
    source = %{source | value: validate_performer(id, source.value, client_id)}
    %{immunization | source: source}
  end

  def validate_source(%Immunization{} = immunization, _) do
    add_validations(immunization, :source, source: [primary_source: immunization.primary_source])
  end

  def validate_performer(id, %Reference{} = performer, client_id) do
    identifier =
      add_validations(
        performer.identifier,
        :value,
        employee: [legal_entity_id: client_id, ets_key: "immunization_#{id}_performer_employee"]
      )

    %{performer | identifier: identifier}
  end

  def validate_reactions(%Immunization{} = immunization, observations, patient_id) do
    now = DateTime.utc_now()
    reactions = immunization.reactions

    reactions =
      Enum.map(reactions, fn reaction ->
        detail = reaction.detail

        identifier =
          add_validations(
            detail.identifier,
            :value,
            observation_reference: [patient_id: patient_id, observations: observations]
          )

        add_validations(
          %{reaction | detail: %{detail | identifier: identifier}},
          :date,
          datetime: [less_than_or_equal_to: now, message: "Date of reaction must be in past"]
        )
      end)

    %{immunization | reactions: reactions}
  end
end
