defmodule Api.Web.JobView do
  @moduledoc false

  use ApiWeb, :view
  alias Core.Job

  def render("create.json", %{job: %Job{_id: id, status: status} = job}) do
    job
    |> Map.take(~w(inserted_at updated_at)a)
    |> Map.put(:status, Job.status_to_string(status))
    |> Map.put(:id, id)
  end
end
