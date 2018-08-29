defmodule ApiWeb.Router do
  @moduledoc false

  use ApiWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:required_header, "x-consumer-id")
    plug(:put_user_id)
    plug(:put_client_id)
  end

  scope "/api", Api.Web do
    pipe_through(:api)

    post("/patients/:patient_id/encounter_package", EncounterController, :create)
    post("/patients/:patient_id/episodes", EpisodeController, :create)
    get("/patients/:patient_id/episodes", EpisodeController, :index)
    get("/patients/:patient_id/episodes/:id", EpisodeController, :show)

    get("/jobs/:id", JobController, :show)
  end
end
