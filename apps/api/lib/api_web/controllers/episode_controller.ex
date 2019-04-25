defmodule Api.Web.EpisodeController do
  @moduledoc false

  use ApiWeb, :controller

  alias Api.Web.JobView
  alias Core.Episode
  alias Core.Patients.Episodes
  alias Core.Patients.Episodes.Producer
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def index(conn, params) do
    with {:ok, %Page{entries: episodes} = paging} <- Episodes.list(params) do
      render(conn, "index.json", episodes: episodes, paging: paging)
    end
  end

  def create(conn, params) do
    with {:ok, job} <- Producer.produce_create_episode(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("details.json", job: job)
    end
  end

  def show(conn, %{"patient_id_hash" => patient_id_hash, "id" => id}) do
    with {:ok, %Episode{} = episode} <- Episodes.get_by_id(patient_id_hash, id) do
      render(conn, "show.json", episode: episode)
    end
  end

  def update(conn, params) do
    {url_params, request_params, conn_params} = get_params(conn, params)

    with {:ok, job} <- Producer.produce_update_episode(url_params, request_params, conn_params) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("details.json", job: job)
    end
  end

  def close(conn, params) do
    {url_params, request_params, conn_params} = get_params(conn, params)

    with {:ok, job} <- Producer.produce_close_episode(url_params, request_params, conn_params) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("details.json", job: job)
    end
  end

  def cancel(conn, params) do
    {url_params, request_params, conn_params} = get_params(conn, params)

    with {:ok, job} <- Producer.produce_cancel_episode(url_params, request_params, conn_params) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("details.json", job: job)
    end
  end

  defp get_params(conn, %{"id" => id, "patient_id_hash" => patient_id_hash, "patient_id" => patient_id} = params) do
    url_params = %{"id" => id, "patient_id" => patient_id, "patient_id_hash" => patient_id_hash}
    request_params = Map.drop(params, ~w(id patient_id patient_id_hash))
    conn_params = %{"user_id" => conn.private[:user_id], "client_id" => conn.private[:client_id]}
    {url_params, request_params, conn_params}
  end
end
