defmodule Api.Web.JobView do
  @moduledoc false

  use ApiWeb, :view
  alias Core.Job

  def render("create.json", %{job: %Job{_id: id, status: status} = job}) do
    job
    |> Map.take(~w(inserted_at updated_at)a)
    |> Map.merge(%{id: to_string(id), status: Job.status_to_string(status)})
  end

  def render("cancel.json", %{job: %Job{_id: id, status: status} = job}) do
    job
    |> Map.take(~w(inserted_at updated_at)a)
    |> Map.merge(%{id: to_string(id), status: Job.status_to_string(status)})
  end

  def render("details.json", %{job: job}) do
    %{
      eta: job.eta,
      status: Job.status_to_string(job.status),
      status_code: job.status_code
    }
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

  def render_response(%{response: %{"response_data" => data}}), do: %{response_data: data}
  def render_response(%Job{status_code: 200, response: response}), do: %{links: Map.get(response, "links", [])}

  def render_response(%Job{_id: id}) do
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
