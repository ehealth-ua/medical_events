defmodule Core.TestViews.CancelEncounterPackageView do
  @moduledoc false

  alias Core.DateView
  alias Core.DiagnosisView
  alias Core.ReferenceView
  alias Core.UUIDView

  def render(:encounter, encounter) do
    %{
      id: UUIDView.render(encounter.id),
      status: encounter.status,
      date: DateTime.to_iso8601(encounter.date),
      explanatory_letter: encounter.explanatory_letter,
      cancellation_reason: ReferenceView.render(encounter.cancellation_reason),
      visit: ReferenceView.render(encounter.visit),
      episode: ReferenceView.render(encounter.episode),
      class: ReferenceView.render(encounter.class),
      type: ReferenceView.render(encounter.type),
      incoming_referrals: ReferenceView.render(encounter.incoming_referrals),
      performer: ReferenceView.render(encounter.performer),
      reasons: ReferenceView.render(encounter.reasons),
      diagnoses: Enum.map(encounter.diagnoses, &DiagnosisView.render/1),
      actions: ReferenceView.render(encounter.actions),
      division: ReferenceView.render(encounter.division),
      prescriptions: encounter.prescriptions,
      supporting_info: ReferenceView.render(encounter.supporting_info)
    }
    |> ReferenceView.remove_display_values()
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
      |> ReferenceView.remove_display_values()
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
      |> ReferenceView.remove_display_values()
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
        legal_entity: ReferenceView.render(immunization.legal_entity),
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
      |> ReferenceView.remove_display_values()
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
      |> ReferenceView.remove_display_values()
    end
  end

  def render(:risk_assessments, risk_assessments) do
    risk_assessment_fields = ~w(
      status
      mitigation
      comment
    )a

    for risk_assessment <- risk_assessments do
      risk_assessment_data = %{
        id: UUIDView.render(risk_assessment.id),
        context: ReferenceView.render(risk_assessment.context),
        code: ReferenceView.render(risk_assessment.code),
        asserted_date: DateView.render_datetime(risk_assessment.asserted_date),
        method: ReferenceView.render(risk_assessment.method),
        performer: ReferenceView.render(risk_assessment.performer),
        basis: ReferenceView.render(risk_assessment.basis),
        predictions: ReferenceView.render(risk_assessment.predictions)
      }

      risk_assessment
      |> Map.take(risk_assessment_fields)
      |> Map.merge(risk_assessment_data)
      |> Map.merge(ReferenceView.render_reason(risk_assessment.reason))
      |> ReferenceView.remove_display_values()
    end
  end

  def render(:devices, devices) do
    device_fields = ~w(
      status
      primary_source
      lot_number
      manufacturer
      model
      version
      note
    )a

    for device <- devices do
      device_data = %{
        id: UUIDView.render(device.id),
        context: ReferenceView.render(device.context),
        asserted_date: DateView.render_datetime(device.asserted_date),
        usage_period: ReferenceView.render(device.usage_period),
        type: ReferenceView.render(device.type),
        manufacture_date: DateView.render_datetime(device.manufacture_date),
        expiration_date: DateView.render_datetime(device.expiration_date)
      }

      device
      |> Map.take(device_fields)
      |> Map.merge(device_data)
      |> Map.merge(ReferenceView.render_source(device.source))
      |> ReferenceView.remove_display_values()
    end
  end

  def render(:medication_statements, medication_statements) do
    medication_statement_fields = ~w(
      status
      effective_period
      primary_source
      note
      dosage
    )a

    for medication_statement <- medication_statements do
      medication_statement_data = %{
        id: UUIDView.render(medication_statement.id),
        based_on: ReferenceView.render(medication_statement.based_on),
        medication_code: ReferenceView.render(medication_statement.medication_code),
        context: ReferenceView.render(medication_statement.context),
        asserted_date: DateView.render_datetime(medication_statement.asserted_date)
      }

      medication_statement
      |> Map.take(medication_statement_fields)
      |> Map.merge(medication_statement_data)
      |> Map.merge(ReferenceView.render_source(medication_statement.source))
      |> ReferenceView.remove_display_values()
    end
  end

  def render(:diagnostic_reports, diagnostic_reports) do
    diagnostic_report_fields = ~w(
      status
      primary_source
      conclusion
    )a

    for diagnostic_report <- diagnostic_reports do
      diagnostic_report_data = %{
        id: UUIDView.render(diagnostic_report.id),
        based_on: ReferenceView.render(diagnostic_report.based_on),
        origin_episode: ReferenceView.render(diagnostic_report.origin_episode),
        category: ReferenceView.render(diagnostic_report.category),
        code: ReferenceView.render(diagnostic_report.code),
        encounter: ReferenceView.render(diagnostic_report.encounter),
        issued: DateView.render_datetime(diagnostic_report.issued),
        recorded_by: ReferenceView.render(diagnostic_report.recorded_by),
        results_interpreter: ReferenceView.render(diagnostic_report.results_interpreter),
        managing_organization: ReferenceView.render(diagnostic_report.managing_organization),
        conclusion_code: ReferenceView.render(diagnostic_report.conclusion_code)
      }

      diagnostic_report
      |> Map.take(diagnostic_report_fields)
      |> Map.merge(diagnostic_report_data)
      |> Map.merge(ReferenceView.render_effective_at(diagnostic_report.effective))
      |> Map.merge(ReferenceView.render_source(diagnostic_report.source))
      |> ReferenceView.remove_display_values()
    end
  end
end
