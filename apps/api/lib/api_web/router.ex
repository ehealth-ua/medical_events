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

    scope "/" do
      pipe_through(:authorize_party)

      get("/patients/:patient_id/conditions", ConditionController, :index)
      get("/patients/:patient_id/conditions/:id", ConditionController, :show)

      get("/patients/:patient_id/episodes", EpisodeController, :index)
      get("/patients/:patient_id/episodes/:id", EpisodeController, :show)

      get("/patients/:patient_id/observations", ObservationController, :index)
      get("/patients/:patient_id/observations/:id", ObservationController, :show)

      get("/patients/:patient_id/encounters", EncounterController, :index)
      get("/patients/:patient_id/encounters/:id", EncounterController, :show)

      get("/patients/:patient_id/immunizations", ImmunizationController, :index)
      get("/patients/:patient_id/immunizations/:id", ImmunizationController, :show)

      get("/patients/:patient_id/allergy_intolerances", AllergyIntoleranceController, :index)
      get("/patients/:patient_id/allergy_intolerances/:id", AllergyIntoleranceController, :show)
    end

    patch("/patients/:patient_id/episodes/:id", EpisodeController, :update)
    patch("/patients/:patient_id/episodes/:id/actions/close", EpisodeController, :close)
    patch("/patients/:patient_id/episodes/:id/actions/cancel", EpisodeController, :cancel)
    patch("/patients/:patient_id/encounter_package", EncounterController, :cancel)

    scope "/patients/:patient_id/service_requests" do
      post("/", ServiceRequestController, :create)
      patch("/:service_request_id/actions/use", ServiceRequestController, :use)
    end

    get("/jobs/:id", JobController, :show)

    scope "/patients/:patient_id/summary" do
      pipe_through(:summary)
      get("/immunizations", SummaryController, :list_immunizations)
      get("/immunizations/:id", ImmunizationController, :show)

      get("/allergy_intolerances", SummaryController, :list_allergy_intolerances)
      get("/allergy_intolerances/:id", AllergyIntoleranceController, :show)

      get("/conditions", SummaryController, :list_conditions)
      get("/conditions/:id", SummaryController, :show_condition)

      get("/observations", SummaryController, :list_observations)
      get("/observations/:id", SummaryController, :show_observation)

      get("/diagnoses", SummaryController, :list_diagnoses)
    end
  end
end
