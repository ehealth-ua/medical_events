defmodule Api.Web.JobView do
  @moduledoc false

  use ApiWeb, :view
  alias Core.Job
  alias Core.Jobs

  def render("create.json", %{job: %Job{_id: id, status: status} = job}) do
    job
    |> Map.take(~w(inserted_at updated_at)a)
    |> Map.put(:status, Job.status_to_string(status))
    |> Map.put(:id, id)
  end

  def render("details.json", %{job: job}) do
    %{
      eta: job.eta,
      links: Jobs.fetch_links(job.response),
      status: Job.status_to_string(job.status),
      status_code: job.status_code
    }
  end

  def render("details_error.json", %{job: job}) do
    %{
      eta: job.eta,
      errors: job.response,
      status: Job.status_to_string(job.status),
      status_code: job.status_code
    }
  end
end
