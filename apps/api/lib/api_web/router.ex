defmodule ApiWeb.Router do
  @moduledoc false

  use ApiWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:required_header, "x-consumer-id")
  end

  scope "/api", Api.Web do
    pipe_through(:api)

    post("/patients/:patient_id/visits", VisitController, :create)
    post("/patients/:patient_id/episodes", EpisodeController, :create)
  end
end
