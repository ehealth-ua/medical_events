defmodule Api.Web.EncounterController do
  @moduledoc false

  use ApiWeb, :controller

  alias Api.Web.JobView
  alias Core.Encounter
  alias Core.Patients
  alias Core.Patients.Encounters
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def index(conn, params) do
    with {:ok, %Page{entries: encounters} = paging} <- Encounters.list(params) do
      render(conn, "index.json", encounters: encounters, paging: paging)
    end
  end

  def show(conn, %{"patient_id" => patient_id, "id" => encounter_id}) do
    with {:ok, encounter} <- Encounters.get(patient_id, encounter_id) do
      render(conn, "show.json", encounter: encounter)
    end
  end

  def create(conn, params) do
    with {:ok, job} <- Patients.produce_create_package(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end

  def cancel(conn, params) do
    with {:ok, job} <- Patients.produce_cancel_package(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("details.json", job: job)
    end
  end
end
