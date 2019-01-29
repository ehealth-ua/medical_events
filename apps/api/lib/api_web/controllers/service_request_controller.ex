defmodule Api.Web.ServiceRequestController do
  @moduledoc false

  use ApiWeb, :controller

  alias Api.Web.JobView
  alias Core.ServiceRequest
  alias Core.ServiceRequests
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def index(conn, params) do
    with {:ok, %Page{entries: entries} = paging} <- ServiceRequests.list(params) do
      render(conn, "index.json", service_requests: entries, paging: paging)
    end
  end

  def show(conn, %{"patient_id_hash" => patient_id_hash, "episode_id" => episode_id, "service_request_id" => id}) do
    with {:ok, %ServiceRequest{} = service_request} <-
           ServiceRequests.get_by_episode_id(patient_id_hash, episode_id, id) do
      render(conn, "show.json", service_request: service_request)
    end
  end

  def search(conn, params) do
    with {:ok, %Page{entries: entries} = paging} <- ServiceRequests.search(params) do
      render(conn, "index.json", service_requests: entries, paging: paging)
    end
  end

  def create(conn, params) do
    with {:ok, job} <-
           ServiceRequests.produce_create_service_request(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end

  def use(conn, params) do
    with {:ok, job} <-
           ServiceRequests.produce_use_service_request(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end

  def release(conn, params) do
    with {:ok, job} <-
           ServiceRequests.produce_release_service_request(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end

  def recall(conn, params) do
    with {:ok, job} <-
           ServiceRequests.produce_recall_service_request(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end

  def cancel(conn, params) do
    with {:ok, job} <-
           ServiceRequests.produce_cancel_service_request(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end
end
