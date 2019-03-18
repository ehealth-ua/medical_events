defmodule Api.Web.RiskAssessmentController do
  @moduledoc false

  use ApiWeb, :controller

  alias Core.Patients.RiskAssessments
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def index(conn, params) do
    with {:ok, %Page{entries: risk_assessments} = paging} <- RiskAssessments.list(params) do
      render(conn, "index.json", risk_assessments: risk_assessments, paging: paging)
    end
  end

  def show(conn, %{"patient_id_hash" => patient_id_hash, "id" => risk_assessment_id}) do
    with {:ok, risk_assessment} <- RiskAssessments.get_by_id(patient_id_hash, risk_assessment_id) do
      render(conn, "show.json", risk_assessment: risk_assessment)
    end
  end

  def show_by_episode(conn, params) do
    %{"patient_id_hash" => patient_id_hash, "id" => risk_assessment_id, "episode_id" => episode_id} = params

    with {:ok, risk_assessment} <-
           RiskAssessments.get_by_id_episode_id(patient_id_hash, risk_assessment_id, episode_id) do
      render(conn, "show.json", risk_assessment: risk_assessment)
    end
  end
end
