defmodule Core.Patients.DiagnosticReports.Validations do
  @moduledoc false

  import Core.Schema, only: [add_validations: 3]

  alias Core.DiagnosticReport
  alias Core.EffectiveAt
  alias Core.Executor
  alias Core.Period
  alias Core.Source

  def validate_source(%DiagnosticReport{source: %Source{type: "performer"}} = diagnostic_report, client_id) do
    diagnostic_report =
      add_validations(
        diagnostic_report,
        :source,
        source: [primary_source: diagnostic_report.primary_source, primary_required: "performer"]
      )

    source = diagnostic_report.source
    source = %{source | value: validate_performer(source.value, client_id)}
    %{diagnostic_report | source: source}
  end

  def validate_source(%DiagnosticReport{} = diagnostic_report, _) do
    add_validations(diagnostic_report, :source, source: [primary_source: diagnostic_report.primary_source])
  end

  def validate_performer(%Executor{type: "reference"} = performer, client_id) do
    %{performer | value: add_employee_validation(performer.value, client_id)}
  end

  def validate_performer(%Executor{} = executor, _), do: executor

  def validate_based_on(%DiagnosticReport{based_on: nil} = diagnostic_report, _), do: diagnostic_report

  def validate_based_on(%DiagnosticReport{based_on: based_on} = diagnostic_report, client_id) do
    now = DateTime.utc_now()

    identifier =
      add_validations(based_on.identifier, :value, service_request_reference: [client_id: client_id, datetime: now])

    %{diagnostic_report | based_on: %{based_on | identifier: identifier}}
  end

  def validate_effective(%DiagnosticReport{effective: %EffectiveAt{type: "effective_period"}} = diagnostic_report) do
    effective = %{diagnostic_report.effective | value: validate_period(diagnostic_report.effective.value)}
    %{diagnostic_report | effective: effective}
  end

  def validate_effective(%DiagnosticReport{} = diagnostic_report), do: diagnostic_report

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

  def validate_issued(%DiagnosticReport{} = diagnostic_report) do
    now = DateTime.utc_now()
    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:diagnostic_report_max_days_passed]

    add_validations(diagnostic_report, :issued,
      datetime: [less_than_or_equal_to: now, message: "Issued must be in past"],
      max_days_passed: [max_days_passed: max_days_passed]
    )
  end

  def validate_recorded_by(%DiagnosticReport{recorded_by: recorded_by} = diagnostic_report, client_id) do
    %{diagnostic_report | recorded_by: add_employee_validation(recorded_by, client_id)}
  end

  def validate_encounter(%DiagnosticReport{encounter: nil} = diagnostic_report, _), do: diagnostic_report

  def validate_encounter(%DiagnosticReport{encounter: encounter} = diagnostic_report, encounter_id) do
    identifier =
      add_validations(encounter.identifier, :value, value: [equals: encounter_id, message: "Invalid reference"])

    %{diagnostic_report | encounter: %{encounter | identifier: identifier}}
  end

  def validate_managing_organization(%DiagnosticReport{managing_organization: nil} = diagnostic_report, _),
    do: diagnostic_report

  def validate_managing_organization(
        %DiagnosticReport{managing_organization: managing_organization} = diagnostic_report,
        client_id
      ) do
    identifier =
      managing_organization.identifier
      |> add_validations(
        :value,
        value: [
          equals: client_id,
          message: "Managing_organization does not correspond to user's legal_entity"
        ],
        legal_entity: [
          status: "ACTIVE",
          messages: [
            status: "LegalEntity is not active"
          ]
        ]
      )

    %{diagnostic_report | managing_organization: %{managing_organization | identifier: identifier}}
  end

  def validate_results_interpreter(
        %DiagnosticReport{results_interpreter: %Executor{type: "reference"} = results_interpreter} = diagnostic_report,
        client_id
      ) do
    %{
      diagnostic_report
      | results_interpreter: %{
          results_interpreter
          | value: add_employee_validation(results_interpreter.value, client_id)
        }
    }
  end

  def validate_results_interpreter(%DiagnosticReport{} = diagnostic_report, _), do: diagnostic_report

  defp add_employee_validation(field, client_id) do
    identifier =
      add_validations(
        field.identifier,
        :value,
        employee: [
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee is not an active doctor",
            status: "Employee is not an active doctor",
            legal_entity_id: "Employee #{field.identifier.value} doesn't belong to your legal entity"
          ]
        ]
      )

    %{field | identifier: identifier}
  end
end
