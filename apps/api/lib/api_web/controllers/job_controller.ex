defmodule Api.Web.JobController do
  @moduledoc false

  use ApiWeb, :controller

  alias Core.Job
  alias Core.Jobs

  action_fallback(Api.Web.FallbackController)

  def show(conn, %{"id" => id}) do
    with {:ok, %Job{} = job} <- Jobs.get_by_id(id),
         {status, template} <- map_http_response_code(job) do
      conn
      |> put_status(status)
      |> render(template, job: job)
    end
  end

  defp map_http_response_code(%Job{status_code: 200}), do: {303, "details.json"}
  defp map_http_response_code(%Job{status_code: 202}), do: {200, "details.json"}
  defp map_http_response_code(%Job{status_code: code}) when code in [404, 422], do: {200, "details_error.json"}

  defp map_http_response_code(%Job{status_code: code}),
    do: {:error, {:not_implemented, "Job status_code `#{code}` not implemented for response"}}
end
