defmodule Api.Web.EpisodeController do
  @moduledoc false

  use ApiWeb, :controller
  alias Api.Web.JobView
  alias Core.Patients
  alias Core.Patients.Episodes
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def index(conn, %{"patient_id" => patient_id} = params) do
    with %Page{} = paging <- Episodes.list(params) do
      render(
        conn,
        "index.json",
        paging: paging,
        patient_id: patient_id
      )
    end
  end

  def create(conn, params) do
    with {:ok, job} <- Patients.produce_create_episode(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end

  def show(conn, %{"patient_id" => patient_id, "id" => id}) do
    with {:ok, episode} <- Episodes.get(patient_id, id) do
      render(conn, "show.json", episode: episode, patient_id: patient_id)
    end
  end

  def update(conn, params) do
    with {:ok, job} <- Patients.produce_update_episode(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end
end
