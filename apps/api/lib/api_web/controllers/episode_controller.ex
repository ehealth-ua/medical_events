defmodule Api.Web.EpisodeController do
  @moduledoc false

  use ApiWeb, :controller
  alias Api.Web.JobView
  alias Core.Patients
  alias Core.Patients.Episodes
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def index(conn, %{"patient_id" => patient_id} = params) do
    with {:ok, episodes, paging} <- Episodes.list(params),
         %{
           "total_pages" => total_pages,
           "total_entries" => total_entries,
           "page_size" => page_size,
           "page_number" => page_number
         } = paging do
      render(
        conn,
        "index.json",
        episodes: episodes,
        patient_id: patient_id,
        paging: %Page{
          entries: episodes,
          page_number: page_number,
          page_size: page_size,
          total_entries: total_entries,
          total_pages: total_pages
        }
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
