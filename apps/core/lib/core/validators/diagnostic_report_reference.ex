defmodule Core.Validators.DiagnosticReportReference do
  @moduledoc false

  alias Core.DiagnosticReport
  alias Core.Patients.DiagnosticReports
  import Core.ValidationError

  @status_entered_in_error DiagnosticReport.status(:entered_in_error)

  def validate(diagnostic_report_id, options) do
    patient_id_hash = Keyword.get(options, :patient_id_hash)

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
