defmodule Api.Web.SummaryController do
  @moduledoc false

  use ApiWeb, :controller

  alias Api.Web.AllergyIntoleranceView
  alias Api.Web.ConditionView
  alias Api.Web.DeviceView
  alias Api.Web.DiagnosisView
  alias Api.Web.DiagnosticReportView
  alias Api.Web.EpisodeView
  alias Api.Web.ImmunizationView
  alias Api.Web.MedicationStatementView
  alias Api.Web.ObservationView
  alias Api.Web.RiskAssessmentView
  alias Core.Conditions
  alias Core.Diagnoses
  alias Core.Observations
  alias Core.Patients.AllergyIntolerances
  alias Core.Patients.Devices
  alias Core.Patients.DiagnosticReports
  alias Core.Patients.Episodes
  alias Core.Patients.Immunizations
  alias Core.Patients.MedicationStatements
  alias Core.Patients.RiskAssessments
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def list_episodes(conn, params) do
    with {:ok, %Page{entries: episodes} = paging} <- Episodes.list(params, :episode_get_summary) do
      conn
      |> put_view(EpisodeView)
      |> render("summary.json", episodes: episodes, paging: paging)
    end
  end

  def list_immunizations(conn, params) do
    with {:ok, %Page{entries: immunizations} = paging} <- Immunizations.list(params, :immunization_summary) do
      conn
      |> put_view(ImmunizationView)
      |> render("index.json", immunizations: immunizations, paging: paging)
    end
  end

  def list_allergy_intolerances(conn, params) do
    with {:ok, %Page{entries: allergy_intolerances} = paging} <-
           AllergyIntolerances.list(params, :allergy_intolerance_summary) do
      conn
      |> put_view(AllergyIntoleranceView)
      |> render("index.json", allergy_intolerances: allergy_intolerances, paging: paging)
    end
  end

  def list_risk_assessments(conn, params) do
    with {:ok, %Page{entries: risk_assessments} = paging} <- RiskAssessments.list(params, :risk_assessment_summary) do
      conn
      |> put_view(RiskAssessmentView)
      |> render("index.json", risk_assessments: risk_assessments, paging: paging)
    end
  end

  def list_conditions(conn, params) do
    with {:ok, %Page{entries: conditions} = paging} <- Conditions.summary(params) do
      conn
      |> put_view(ConditionView)
      |> render("index.json", conditions: conditions, paging: paging)
    end
  end

  def show_condition(conn, %{"patient_id_hash" => patient_id_hash, "id" => condition_id}) do
    with {:ok, condition} <- Conditions.get_summary(patient_id_hash, condition_id) do
      conn
      |> put_view(ConditionView)
      |> render("show.json", condition: condition)
    end
  end

  def list_observations(conn, params) do
    with {:ok, %Page{entries: observations} = paging} <- Observations.summary(params) do
      conn
      |> put_view(ObservationView)
      |> render("index.json", observations: observations, paging: paging)
    end
  end

  def show_observation(conn, %{"patient_id_hash" => patient_id_hash, "id" => observation_id}) do
    with {:ok, observation} <- Observations.get_summary(patient_id_hash, observation_id) do
      conn
      |> put_view(ObservationView)
      |> render("show.json", observation: observation)
    end
  end

  def list_diagnoses(conn, params) do
    with {:ok, %Page{entries: diagnoses} = paging} <- Diagnoses.list_active_diagnoses(params) do
      conn
      |> put_view(DiagnosisView)
      |> render("diagnoses.json", diagnoses: diagnoses, paging: paging)
    end
  end

  def list_devices(conn, params) do
    with {:ok, %Page{entries: devices} = paging} <- Devices.list(params, :device_summary) do
      conn
      |> put_view(DeviceView)
      |> render("index.json", devices: devices, paging: paging)
    end
  end

  def list_medication_statements(conn, params) do
    with {:ok, %Page{entries: medication_statements} = paging} <-
           MedicationStatements.list(params, :medication_statement_summary) do
      conn
      |> put_view(MedicationStatementView)
      |> render("index.json", medication_statements: medication_statements, paging: paging)
    end
  end

  def list_diagnostic_reports(conn, params) do
    with {:ok, %Page{entries: diagnostic_reports} = paging} <-
           DiagnosticReports.list(params, :diagnostic_report_summary) do
      conn
      |> put_view(DiagnosticReportView)
      |> render("index.json", diagnostic_reports: diagnostic_reports, paging: paging)
    end
  end

  def show_diagnostic_report(conn, %{"patient_id_hash" => patient_id_hash, "id" => diagnostic_report_id}) do
    with {:ok, diagnostic_report} <- DiagnosticReports.get_summary(patient_id_hash, diagnostic_report_id) do
      conn
      |> put_view(DiagnosticReportView)
      |> render("show.json", diagnostic_report: diagnostic_report)
    end
  end
end
