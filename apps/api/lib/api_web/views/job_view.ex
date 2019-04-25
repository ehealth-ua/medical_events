defmodule Api.Web.JobView do
  @moduledoc false

  use ApiWeb, :view
  alias Core.Job

  @job_status_pending Job.status(:pending)
  @job_status_processed Job.status(:processed)

  def render("details.json", %{job: job}) do
    %{
      eta: job.eta,
      status: Job.status_to_string(job.status)
    }
    |> add_status_code(job)
    |> Map.merge(render_response(job))
  end

  def render("details_error.json", %{job: job}) do
    %{
      eta: job.eta,
      errors: job.response,
      status: Job.status_to_string(job.status),
      status_code: job.status_code
    }
  end

  defp add_status_code(response, %Job{status: @job_status_pending}), do: response
  defp add_status_code(response, %Job{} = job), do: Map.put(response, :status_code, job.status_code)

  defp render_response(%{response: %{"response_data" => data}}), do: %{response_data: data}

  defp render_response(%Job{status: @job_status_processed, response: response}),
    do: %{links: Map.get(response, "links", [])}

  defp render_response(%Job{_id: id}) do
    %{
      links: [
        %{
          entity: "job",
          href: "/jobs/#{id}"
        }
      ]
    }
  end
end
