defmodule Core.JobsTest do
  @moduledoc false

  use Core.ModelCase
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.ApprovalCreateJob
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Jobs.JobUpdateStatusJob

  describe "create job" do
    test "success create job" do
      data = %{}
      hash = :md5 |> :crypto.hash(:erlang.term_to_binary(data)) |> Base.url_encode64(padding: false)
      insert(:job, hash: hash, status: Job.status(:processed))

      assert {:ok, job, _} = Jobs.create(EpisodeCreateJob, data)
      job_id = to_string(job._id)
      assert {:job_exists, ^job_id} = Jobs.create(EpisodeCreateJob, data)
    end

    test "success update job with response as map" do
      links = [
        %{
          "entity" => "approval",
          "data" => %{
            access_level: "read",
            expires_at: 1_550_048_855,
            granted_resources: [
              %{
                display_value: nil,
                identifier: %{
                  type: %{
                    coding: [%{code: "episode_of_care", system: "eHealth/resources"}],
                    text: nil
                  },
                  value: "a8dd7a9a-6d4c-49b5-a3b1-ffd94ca14592"
                }
              },
              %{
                display_value: nil,
                identifier: %{
                  type: %{
                    coding: [%{code: "episode_of_care", system: "eHealth/resources"}],
                    text: nil
                  },
                  value: "3b5b0404-7f02-40c5-a532-a4038ebf4540"
                }
              }
            ],
            granted_to: %{
              display_value: nil,
              identifier: %{
                type: %{
                  coding: [%{code: "employee", system: "eHealth/resources"}],
                  text: nil
                },
                value: "0f9bb17c-cdd9-407f-a02d-134b11e82f8c"
              }
            },
            id: "4520412e-a09f-4521-94db-3a7d19148ec1",
            reason: nil,
            status: "new"
          }
        }
      ]

      hash = :md5 |> :crypto.hash(:erlang.term_to_binary(%{})) |> Base.url_encode64(padding: false)
      job = insert(:job, hash: hash, status: Job.status(:pending))
      job_id = to_string(job._id)

      assert {:ok, %{matched_count: 1, modified_count: 1}} =
               Jobs.update(job_id, Job.status(:processed), %{"links" => links}, 200)

      assert {:ok, job} = Jobs.get_by_id(job_id)

      assert Map.get(job.response, "links") ==
               links
               |> Jason.encode!()
               |> Jason.decode!()

      assert job.status == Job.status(:processed)
      assert job.status_code == 200
    end

    test "success update job with response as string" do
      response = "response"

      hash = :md5 |> :crypto.hash(:erlang.term_to_binary(%{})) |> Base.url_encode64(padding: false)
      job = insert(:job, hash: hash, status: Job.status(:pending))
      job_id = to_string(job._id)

      assert {:ok, %{matched_count: 1, modified_count: 1}} = Jobs.update(job_id, Job.status(:processed), response, 200)

      assert {:ok, job} = Jobs.get_by_id(job_id)

      assert job.response == response
      assert job.status == Job.status(:processed)
      assert job.status_code == 200
    end

    test "success update status job" do
      data = %{
        "status" => Job.status(:processed),
        "response" => %{
          "links" => [
            %{
              "entity" => "approval",
              "data" => %{}
            }
          ]
        },
        "status_code" => 200,
        "timestamp" => DateTime.utc_now()
      }

      assert {:ok, job, _} = Jobs.create(ApprovalCreateJob, data)

      job_id = to_string(job._id)

      event = %JobUpdateStatusJob{
        request_id: nil,
        _id: job_id,
        response: data["response"],
        status: data["status"],
        status_code: data["status_code"]
      }

      assert :ok = Jobs.update_status(event)
      assert {:ok, job} = Jobs.get_by_id(job_id)
      assert job.status == Job.status(:processed)
      assert job.status_code == 200
    end
  end
end
