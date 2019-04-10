defmodule Api.Web.DiagnosticReportView do
  @moduledoc false

  use ApiWeb, :view

  alias Core.DateView
  alias Core.ReferenceView
  alias Core.UUIDView

  def render("index.json", %{diagnostic_reports: diagnostic_reports}) do
    render_many(diagnostic_reports, __MODULE__, "show.json", as: :diagnostic_report)
  end

  def render("show.json", %{diagnostic_report: diagnostic_report}) do
    diagnostic_report_fields = ~w(
      status
      primary_source
      conclusion
      explanatory_letter
      inserted_at
      updated_at
    )a

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
      conclusion_code: ReferenceView.render(diagnostic_report.conclusion_code),
      cancellation_reason: ReferenceView.render(diagnostic_report.cancellation_reason)
    }

    diagnostic_report
    |> Map.take(diagnostic_report_fields)
    |> Map.merge(diagnostic_report_data)
    |> Map.merge(ReferenceView.render_effective_at(diagnostic_report.effective))
    |> Map.merge(ReferenceView.render_source(diagnostic_report.source))
  end
end
