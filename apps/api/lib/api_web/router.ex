defmodule ApiWeb.Router do
  @moduledoc false

  use ApiWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:required_header, "x-consumer-id")
    plug(:put_user_id)
    plug(:put_client_id)
    plug(Api.Web.Plugs.PatientIdHasher)
  end

  pipeline :authorize_party do
    plug(Api.Web.Plugs.AuthorizeParty)
  end

  pipeline :summary do
    plug(Api.Web.Plugs.PatientExists)
  end

  scope "/api", Api.Web do
    pipe_through(:api)

    post("/patients/:patient_id/encounter_package", EncounterController, :create)
    post("/patients/:patient_id/episodes", EpisodeController, :create)
    post("/patients/:patient_id/diagnostic_report_package", DiagnosticReportController, :create)

    scope "/" do
      pipe_through(:authorize_party)

      get("/patients/:patient_id/diagnostic_reports", DiagnosticReportController, :index)
      get("/patients/:patient_id/diagnostic_reports/:id", DiagnosticReportController, :show)
    end

    get("/patients/:patient_id/conditions", ConditionController, :index)
    get("/patients/:patient_id/conditions/:id", ConditionController, :show)

    get("/patients/:patient_id/observations", ObservationController, :index)
    get("/patients/:patient_id/observations/:id", ObservationController, :show)

    get("/patients/:patient_id/encounters", EncounterController, :index)
    get("/patients/:patient_id/encounters/:id", EncounterController, :show)

    get("/patients/:patient_id/immunizations", ImmunizationController, :index)
    get("/patients/:patient_id/immunizations/:id", ImmunizationController, :show)

    get("/patients/:patient_id/allergy_intolerances", AllergyIntoleranceController, :index)
    get("/patients/:patient_id/allergy_intolerances/:id", AllergyIntoleranceController, :show)

    get("/patients/:patient_id/risk_assessments", RiskAssessmentController, :index)
    get("/patients/:patient_id/risk_assessments/:id", RiskAssessmentController, :show)

    get("/patients/:patient_id/devices", DeviceController, :index)
    get("/patients/:patient_id/devices/:id", DeviceController, :show)

    get("/patients/:patient_id/medication_statements", MedicationStatementController, :index)
    get("/patients/:patient_id/medication_statements/:id", MedicationStatementController, :show)

    get("/patients/:patient_id/episodes", EpisodeController, :index)
    get("/patients/:patient_id/episodes/:id", EpisodeController, :show)

    scope "/patients/:patient_id/episodes/:episode_id", as: :episode_context do
      get("/encounters", EncounterController, :index)
      get("/encounters/:id", EncounterController, :show_by_episode)

      get("/conditions", ConditionController, :index)
      get("/conditions/:id", ConditionController, :show_by_episode)

      get("/observations", ObservationController, :index)
      get("/observations/:id", ObservationController, :show_by_episode)

      get("/immunizations", ImmunizationController, :index)
      get("/immunizations/:id", ImmunizationController, :show_by_episode)

      get("/allergy_intolerances", AllergyIntoleranceController, :index)
      get("/allergy_intolerances/:id", AllergyIntoleranceController, :show_by_episode)

      get("/risk_assessments", RiskAssessmentController, :index)
      get("/risk_assessments/:id", RiskAssessmentController, :show_by_episode)

      get("/devices", DeviceController, :index)
      get("/devices/:id", DeviceController, :show_by_episode)

      get("/medication_statements", MedicationStatementController, :index)
      get("/medication_statements/:id", MedicationStatementController, :show_by_episode)
    end

    patch("/patients/:patient_id/episodes/:id", EpisodeController, :update)
    patch("/patients/:patient_id/episodes/:id/actions/close", EpisodeController, :close)
    patch("/patients/:patient_id/episodes/:id/actions/cancel", EpisodeController, :cancel)
    patch("/patients/:patient_id/encounter_package", EncounterController, :cancel)
    patch("/patients/:patient_id/diagnostic_report_package", DiagnosticReportController, :cancel)

    get(
      "/patients/:patient_id/episodes/:episode_id/service_requests/:service_request_id",
      ServiceRequestController,
      :show
    )

    patch("/service_requests/:service_request_id/actions/use", ServiceRequestController, :use)
    patch("/service_requests/:service_request_id/actions/release", ServiceRequestController, :release)
    patch("/service_requests/:service_request_id/actions/process", ServiceRequestController, :process)
    patch("/service_requests/:service_request_id/actions/complete", ServiceRequestController, :complete)

    get("/patients/:patient_id/episodes/:episode_id/service_requests", ServiceRequestController, :index)
    get("/service_requests", ServiceRequestController, :search)

    scope "/patients/:patient_id/service_requests" do
      get("/", ServiceRequestController, :patient_context_search)
      post("/", ServiceRequestController, :create)
      patch("/:service_request_id/actions/recall", ServiceRequestController, :recall)
      patch("/:service_request_id/actions/cancel", ServiceRequestController, :cancel)
    end

    scope "/patients/:patient_id/approvals" do
      post("/", ApprovalController, :create)
      patch("/:id", ApprovalController, :verify)
      patch("/:id/actions/resend", ApprovalController, :resend)
    end

    get("/jobs/:id", JobController, :show)

    scope "/patients/:patient_id/summary" do
      pipe_through(:summary)

      get("/episodes", SummaryController, :list_episodes)

      get("/immunizations", SummaryController, :list_immunizations)
      get("/immunizations/:id", ImmunizationController, :show)

      get("/allergy_intolerances", SummaryController, :list_allergy_intolerances)
      get("/allergy_intolerances/:id", AllergyIntoleranceController, :show)

      get("/risk_assessments", SummaryController, :list_risk_assessments)
      get("/risk_assessments/:id", RiskAssessmentController, :show)

      get("/conditions", SummaryController, :list_conditions)
      get("/conditions/:id", SummaryController, :show_condition)

      get("/observations", SummaryController, :list_observations)
      get("/observations/:id", SummaryController, :show_observation)

      get("/devices", SummaryController, :list_devices)
      get("/devices/:id", DeviceController, :show)

      get("/medication_statements", SummaryController, :list_medication_statements)
      get("/medication_statements/:id", MedicationStatementController, :show)

      get("/diagnostic_reports", SummaryController, :list_diagnostic_reports)
      get("/diagnostic_reports/:id", SummaryController, :show_diagnostic_report)

      get("/diagnoses", SummaryController, :list_diagnoses)
    end
  end
end
