defmodule Api.Web.EncounterController do
  @moduledoc false

  use ApiWeb, :controller
  alias Api.Web.JobView
  alias Core.Patients

  action_fallback(Api.Web.FallbackController)

  def create(conn, params) do
    with {:ok, job} <- Patients.produce_create_package(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end
end
