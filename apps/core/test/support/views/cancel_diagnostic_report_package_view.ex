defmodule Core.TestViews.CancelDiagnosticReportPackageView do
  @moduledoc false

  alias Core.DateView
  alias Core.ReferenceView
  alias Core.UUIDView

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
        diagnostic_report: ReferenceView.render(observation.diagnostic_report),
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

  def render(:diagnostic_report, diagnostic_report) do
    diagnostic_report_fields = ~w(
      status
      primary_source
      conclusion
      explanatory_letter
    )a

    diagnostic_report_data = %{
      id: UUIDView.render(diagnostic_report.id),
      based_on: ReferenceView.render(diagnostic_report.based_on),
      category: ReferenceView.render(diagnostic_report.category),
      code: ReferenceView.render(diagnostic_report.code),
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
    |> ReferenceView.remove_display_values()
  end
end
