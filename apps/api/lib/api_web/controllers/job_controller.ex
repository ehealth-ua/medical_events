defmodule Api.Web.JobController do
  @moduledoc false

  use ApiWeb, :controller

  alias Core.Job
  alias Core.Jobs

  action_fallback(Api.Web.FallbackController)

  def show(conn, %{"id" => id}) do
    with {:ok, %Job{} = job} <- Jobs.get_by_id(id) do
      case job.status_code do
        code when code in [404, 422] ->
          conn
          |> put_status(200)
          |> render("details_error.json", job: job)

        code when code in [200, 203] ->
          conn
          |> put_status(job.status_code)
          |> render("details.json", job: job)

        code ->
          {:error, {:not_implemented, "Job status_code `#{code}` not implemented for response"}}
      end
    end
  end
end
