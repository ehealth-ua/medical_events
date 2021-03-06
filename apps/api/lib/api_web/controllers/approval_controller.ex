defmodule Api.Web.ApprovalController do
  @moduledoc false

  use ApiWeb, :controller

  alias Api.Web.JobView
  alias Core.Approval
  alias Core.Approvals
  alias Core.Approvals.Producer

  action_fallback(Api.Web.FallbackController)

  def create(conn, params) do
    with {:ok, job} <- Producer.produce_create_approval(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("details.json", job: job)
    end
  end

  def verify(conn, params) do
    with {:ok, %Approval{} = _} <- Approvals.verify(params, conn.private[:user_id]) do
      render(conn, "empty.json")
    end
  end

  def resend(conn, params) do
    with {:ok, job} <- Producer.produce_resend_approval(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("details.json", job: job)
    end
  end
end
