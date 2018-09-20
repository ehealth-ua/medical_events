defmodule Core.JobsTest do
  @moduledoc false

  use Core.ModelCase
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.EpisodeCreateJob

  describe "create job" do
    test "success create job" do
      data = %{}
      hash = :md5 |> :crypto.hash(:erlang.term_to_binary(data)) |> Base.url_encode64(padding: false)
      insert(:job, hash: hash, status: Job.status(:processed))

      assert {:ok, job, _} = Jobs.create(EpisodeCreateJob, data)
      job_id = to_string(job._id)
      assert {:job_exists, ^job_id} = Jobs.create(EpisodeCreateJob, data)
    end
  end
end
