defmodule Api.Web.VisitController do
  @moduledoc false

  use ApiWeb, :controller
  alias Core.Patients

  action_fallback(Api.Web.FallbackController)

  def create(conn, params) do
    with {:ok, visit} <- Patients.create_visit(params) do
      render(conn, "create.json", visit: visit)
    end
  end
end
