defmodule Core.Expectations.JobExpectations do
  @moduledoc false

  alias Core.Job
  import Mox
  import ExUnit.Assertions

  def expect_job_update(id, response, code) do
    expect_job_update(id, Job.status(:processed), response, code)
  end

  def expect_job_update(id, status, response, code) do
    expect(WorkerMock, :run, fn _, _, :transaction, args ->
      assert %{
               "actor_id" => _,
               "operations" => [
                 %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
               ]
             } = Jason.decode!(args)

      assert %{"_id" => id} == filter |> Base.decode64!() |> BSON.decode()

      set_bson = set |> Base.decode64!() |> BSON.decode()

      assert %{
               "$set" => %{
                 "status" => ^status,
                 "status_code" => ^code,
                 "response" => ^response
               }
             } = set_bson

      :ok
    end)
  end
end
