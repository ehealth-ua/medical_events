defmodule Api.Web.ServiceRequestController do
  @moduledoc false

  use ApiWeb, :controller

  alias Api.Web.JobView
  alias Core.ServiceRequests

  action_fallback(Api.Web.FallbackController)

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
end
