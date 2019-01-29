defmodule Api.Web.RiskAssessmentView do
  @moduledoc false

  use ApiWeb, :view

  alias Core.DateView
  alias Core.ReferenceView
  alias Core.UUIDView

  def render("index.json", %{risk_assessments: risk_assessments}) do
    render_many(risk_assessments, __MODULE__, "show.json", as: :risk_assessment)
  end

  def render("show.json", %{risk_assessment: risk_assessment}) do
    risk_assessment_fields = ~w(
      status
      mitigation
      comment
      inserted_at
      updated_at
    )a

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
  end
end
