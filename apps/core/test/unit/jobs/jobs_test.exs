defmodule Core.JobsTest do
  @moduledoc false

  use Core.ModelCase
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.EpisodeCreateJob
  import Mox

  describe "create job" do
    test "success create job" do
      data = %{"foo" => "bar"}
      hash = :md5 |> :crypto.hash(:erlang.term_to_binary(data)) |> Base.url_encode64(padding: false)
      insert(:job, hash: hash, status: Job.status(:processed))

      assert {:ok, job, _} = Jobs.create(EpisodeCreateJob, data)
      job_id = to_string(job._id)
      assert {:job_exists, ^job_id} = Jobs.create(EpisodeCreateJob, data)
    end

    test "success update job with response as map" do
      response_data = %{
        "access_level" => "read",
        "expires_at" => 1_550_048_855,
        "granted_resources" => [
          %{
            "display_value" => nil,
            "identifier" => %{
              "type" => %{
                "coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}],
                "text" => nil
              },
              "value" => "a8dd7a9a-6d4c-49b5-a3b1-ffd94ca14592"
            }
          },
          %{
            "display_value" => nil,
            "identifier" => %{
              "type" => %{
                "coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}],
                "text" => nil
              },
              "value" => "3b5b0404-7f02-40c5-a532-a4038ebf4540"
            }
          }
        ],
        "granted_to" => %{
          "display_value" => nil,
          "identifier" => %{
            "type" => %{
              "coding" => [%{"code" => "employee", "system" => "eHealth/resources"}],
              "text" => nil
            },
            "value" => "0f9bb17c-cdd9-407f-a02d-134b11e82f8c"
          }
        },
        "id" => "4520412e-a09f-4521-94db-3a7d19148ec1",
        "reason" => nil,
        "status" => "new"
      }

      hash = :md5 |> :crypto.hash(:erlang.term_to_binary(%{})) |> Base.url_encode64(padding: false)
      job = insert(:job, hash: hash, status: Job.status(:pending))
      job_id = to_string(job._id)

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert [%{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}] =
                 Jason.decode!(args)

        assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

        status = Job.status(:processed)
        set_bson = set |> Base.decode64!() |> BSON.decode()

        assert %{
                 "$set" => %{
                   "status" => ^status,
                   "status_code" => 200,
                   "response" => %{"response_data" => ^response_data}
                 }
               } = set_bson

        :ok
      end)

      assert :ok = Jobs.update(job_id, Job.status(:processed), %{"response_data" => response_data}, 200)
    end

    test "success update job with response as string" do
      response = "response"

      hash = :md5 |> :crypto.hash(:erlang.term_to_binary(%{})) |> Base.url_encode64(padding: false)
      job = insert(:job, hash: hash, status: Job.status(:pending))
      job_id = to_string(job._id)

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert [%{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}] =
                 Jason.decode!(args)

        assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

        status = Job.status(:processed)
        set_bson = set |> Base.decode64!() |> BSON.decode()

        assert %{
                 "$set" => %{
                   "status" => ^status,
                   "status_code" => 200,
                   "response" => ^response
                 }
               } = set_bson

        :ok
      end)

      assert :ok = Jobs.update(job_id, Job.status(:processed), response, 200)
    end
  end
end
