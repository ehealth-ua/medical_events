defmodule Core.Validators.DiagnosticReportContext do
  @moduledoc false

  alias Core.DiagnosticReport
  alias Core.Patients.DiagnosticReports
  import Core.ValidationError

  @status_entered_in_error DiagnosticReport.status(:entered_in_error)

  def validate(diagnostic_report_id, options) do
    diagnostic_reports = Keyword.get(options, :diagnostic_reports) || []
    diagnostic_report_ids = Enum.map(diagnostic_reports, &Map.get(&1, :id))
    patient_id_hash = Keyword.get(options, :patient_id_hash)
    payload_only = Keyword.get(options, :payload_only) || false

    if diagnostic_report_id in diagnostic_report_ids do
      :ok
    else
      check_in_db(patient_id_hash, diagnostic_report_id, options, payload_only)
    end
  end

  defp check_in_db(_, _, options, true), do: error(options, "Invalid reference")

  defp check_in_db(patient_id_hash, diagnostic_report_id, options, _) do
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
