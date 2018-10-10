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

      patch("/patients/:patient_id/encounter_package", EncounterController, :cancel)
    end

    patch("/patients/:patient_id/episodes/:id", EpisodeController, :update)
    patch("/patients/:patient_id/episodes/:id/actions/close", EpisodeController, :close)
    patch("/patients/:patient_id/episodes/:id/actions/cancel", EpisodeController, :cancel)
    patch("/patients/:patient_id/encounter_package", EncounterController, :cancel)

    get("/jobs/:id", JobController, :show)
  end
end
