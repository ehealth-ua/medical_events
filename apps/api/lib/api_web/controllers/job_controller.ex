defmodule Api.Web.JobController do
  @moduledoc false

  use ApiWeb, :controller

  alias Api.Web.JobView
  alias Core.Job
  alias Core.Jobs

  @job_status_pending Job.status(:pending)
  @job_status_processed Job.status(:processed)
  @job_status_failed Job.status(:failed)
  @job_status_failed_with_error Job.status(:failed_with_error)

  action_fallback(Api.Web.FallbackController)

  def show(conn, %{"id" => id}) do
    with {:ok, %Job{} = job} <- Jobs.get_by_id(id),
         {status, template} <- map_http_response_code(job) do
      conn
      |> put_status(status)
      |> put_view(JobView)
      |> render(template, job: job)
    end
  end

  defp map_http_response_code(%Job{
         status: @job_status_processed,
         response: %{"response_data" => _}
       }),
       do: {200, "details.json"}

  defp map_http_response_code(%Job{status: @job_status_processed}), do: {303, "details.json"}
  defp map_http_response_code(%Job{status: @job_status_pending}), do: {200, "details.json"}

  defp map_http_response_code(%Job{status: status, status_code: status_code})
       when status in [@job_status_failed, @job_status_failed_with_error] do
    case status_code do
      409 ->
        {200, "conflict_error.json"}

      500 ->
        {200, "internal_error.json"}

      _ ->
        {200, "details_error.json"}
    end
  end

  defp map_http_response_code(%Job{status_code: code}),
    do: {:error, {:not_implemented, "Job status_code `#{code}` not implemented for response"}}
end
