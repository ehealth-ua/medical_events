defmodule Api.Web.VisitController do
  @moduledoc false

  use ApiWeb, :controller
  alias Core.Patients
  alias Api.Web.RequestView

  action_fallback(Api.Web.FallbackController)

  def create(conn, params) do
    with {:ok, request} <- Patients.produce_create_visit(params) do
      conn
      |> put_status(202)
      |> put_view(RequestView)
      |> render("create.json", request: request)
    end
  end
end
