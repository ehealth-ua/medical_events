defmodule Core.TestViews.CancelEncounterPackageView do
  @moduledoc false

  alias Core.DateView
  alias Core.ReferenceView
  alias Core.UUIDView

  def render(:encounter, encounter) do
    %{
      id: UUIDView.render(encounter.id),
      status: encounter.status,
      date: Date.to_string(encounter.date),
      explanatory_letter: encounter.explanatory_letter,
      cancellation_reason: ReferenceView.render(encounter.cancellation_reason),
      visit: encounter.visit |> ReferenceView.render() |> Map.delete(:display_value),
      episode: encounter.episode |> ReferenceView.render() |> Map.delete(:display_value),
      class: ReferenceView.render(encounter.class),
      type: ReferenceView.render(encounter.type),
      incoming_referrals:
        encounter.incoming_referrals |> ReferenceView.render() |> Enum.map(&Map.delete(&1, :display_value)),
      performer: ReferenceView.render(encounter.performer),
      reasons: ReferenceView.render(encounter.reasons),
      diagnoses: ReferenceView.render(encounter.diagnoses),
      actions: ReferenceView.render(encounter.actions),
      division: ReferenceView.render(encounter.division),
      prescriptions: encounter.prescriptions
    }
  end

  def render(:conditions, conditions) do
    condition_fields = ~w(
      clinical_status
      verification_status
      primary_source
    )a

    for condition <- conditions do
      condition_data = %{
        id: UUIDView.render(condition._id),
        body_sites: ReferenceView.render(condition.body_sites),
        severity: ReferenceView.render(condition.severity),
        stage: ReferenceView.render(condition.stage),
        code: ReferenceView.render(condition.code),
        context: ReferenceView.render(condition.context),
        evidences: ReferenceView.render(condition.evidences),
        asserted_date: DateView.render_datetime(condition.asserted_date),
        onset_date: DateView.render_datetime(condition.onset_date)
      }

      condition
      |> Map.take(condition_fields)
      |> Map.merge(condition_data)
      |> Map.merge(ReferenceView.render_source(condition.source))
    end
  end

  def render(:observations, observations) do
    observation_fields = ~w(
      primary_source
      comment
      issued
      status
    )a

    for observation <- observations do
      observation_data = %{
        id: UUIDView.render(observation._id),
        based_on: ReferenceView.render(observation.based_on),
        method: ReferenceView.render(observation.method),
        categories: ReferenceView.render(observation.categories),
        context: ReferenceView.render(observation.context),
        interpretation: ReferenceView.render(observation.interpretation),
        code: ReferenceView.render(observation.code),
        body_site: ReferenceView.render(observation.body_site),
        reference_ranges: ReferenceView.render(observation.reference_ranges),
        components: ReferenceView.render(observation.components)
      }

      observation
      |> Map.take(observation_fields)
      |> Map.merge(observation_data)
      |> Map.merge(ReferenceView.render_effective_at(observation.effective_at))
      |> Map.merge(ReferenceView.render_source(observation.source))
      |> Map.merge(ReferenceView.render_value(observation.value))
    end
  end

  def render(:immunizations, immunizations) do
    immunization_fields = ~w(
      not_given
      primary_source
      manufacturer
      lot_number
      status
    )a

    for immunization <- immunizations do
      immunization_data = %{
        id: UUIDView.render(immunization.id),
        vaccine_code: ReferenceView.render(immunization.vaccine_code),
        context: ReferenceView.render(immunization.context),
        date: DateView.render_datetime(immunization.date),
        legal_entity: immunization.legal_entity |> ReferenceView.render() |> Map.delete(:display_value),
        expiration_date: DateView.render_datetime(immunization.expiration_date),
        site: ReferenceView.render(immunization.site),
        route: ReferenceView.render(immunization.route),
        dose_quantity: ReferenceView.render(immunization.dose_quantity),
        vaccination_protocols: ReferenceView.render(immunization.vaccination_protocols),
        explanation: ReferenceView.render(immunization.explanation)
      }

      immunization
      |> Map.take(immunization_fields)
      |> Map.merge(immunization_data)
      |> Map.merge(ReferenceView.render_source(immunization.source))
    end
  end

  def render(:allergy_intolerances, allergy_intolerances) do
    allergy_intolerance_fields = ~w(
      verification_status
      clinical_status
      type
      category
      criticality
      primary_source
    )a

    for allergy_intolerance <- allergy_intolerances do
      allergy_intolerance_data = %{
        id: UUIDView.render(allergy_intolerance.id),
        context: ReferenceView.render(allergy_intolerance.context),
        code: ReferenceView.render(allergy_intolerance.code),
        asserted_date: DateView.render_datetime(allergy_intolerance.asserted_date),
        onset_date_time: DateView.render_datetime(allergy_intolerance.onset_date_time),
        last_occurrence: DateView.render_datetime(allergy_intolerance.last_occurrence)
      }

      allergy_intolerance
      |> Map.take(allergy_intolerance_fields)
      |> Map.merge(allergy_intolerance_data)
      |> Map.merge(ReferenceView.render_source(allergy_intolerance.source))
    end
  end
end
