defmodule Core.Validators.DiagnosticReportContext do
  @moduledoc false

  use Vex.Validator
  alias Core.DiagnosticReport
  alias Core.Patients.DiagnosticReports

  @status_entered_in_error DiagnosticReport.status(:entered_in_error)

  def validate(diagnostic_report_id, options) do
    diagnostic_reports = Keyword.get(options, :diagnostic_reports) || []
    diagnostic_report_ids = Enum.map(diagnostic_reports, &Map.get(&1, :_id))
    patient_id_hash = Keyword.get(options, :patient_id_hash)

    if diagnostic_report_id in diagnostic_report_ids do
      :ok
    else
      case DiagnosticReports.get_by_id(patient_id_hash, diagnostic_report_id) do
        nil ->
          error(options, "Diagnostic report with such id is not found")

        {:ok, %{status: @status_entered_in_error}} ->
          error(options, ~s(Diagnostic report in "entered_in_error" status can not be referenced))

        _ ->
          :ok
      end
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
