defmodule Api.Web.ServiceRequestController do
  @moduledoc false

  use ApiWeb, :controller

  alias Api.Web.JobView
  alias Core.ServiceRequest
  alias Core.ServiceRequests
  alias Core.ServiceRequests.Producer
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def index(conn, params) do
    with {:ok, %Page{entries: entries} = paging} <- ServiceRequests.list(params, :service_request_list) do
      render(conn, "index.json", service_requests: entries, paging: paging)
    end
  end

  def show(conn, params) do
    with {:ok, %ServiceRequest{} = service_request} <- ServiceRequests.get_by_episode_id(params) do
      render(conn, "show.json", service_request: service_request)
    end
  end

  def search(conn, params) do
    with {:ok, %Page{entries: entries} = paging} <- ServiceRequests.list(params, :service_request_search) do
      render(conn, "index.json", service_requests: entries, paging: paging)
    end
  end

  def patient_context_search(conn, params) do
    with {:ok, %Page{entries: entries} = paging} <-
           ServiceRequests.list(params, :service_request_patient_context_search) do
      render(conn, "index.json", service_requests: entries, paging: paging)
    end
  end

  def create(conn, params) do
    with {:ok, job} <-
           Producer.produce_create_service_request(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end

  def use(conn, params) do
    with {:ok, job} <-
           Producer.produce_use_service_request(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end

  def release(conn, params) do
    with {:ok, job} <-
           Producer.produce_release_service_request(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end

  def recall(conn, params) do
    with {:ok, job} <-
           Producer.produce_recall_service_request(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end

  def cancel(conn, params) do
    with {:ok, job} <-
           Producer.produce_cancel_service_request(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end

  def process(conn, params) do
    with {:ok, job} <-
           Producer.produce_process_service_request(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end

  def complete(conn, params) do
    with {:ok, job} <-
           Producer.produce_complete_service_request(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("create.json", job: job)
    end
  end
end
