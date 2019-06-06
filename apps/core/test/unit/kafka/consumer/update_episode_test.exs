defmodule Core.Kafka.Consumer.UpdateEpisodeTest do
  @moduledoc false

  use Core.ModelCase

  import Mox
  import Core.Expectations.IlExpectations

  alias Core.Episode
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.EpisodeUpdateJob
  alias Core.Kafka.Consumer
  alias Core.Patients

  @status_pending Job.status(:pending)
  setup :verify_on_exit!

  describe "consume update episode event" do
    test "update with invalid status" do
      episode = build(:episode, status: Episode.status(:closed))
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, episodes: %{UUID.binary_to_string!(episode.id.binary) => episode}, _id: patient_id_hash)
      client_id = UUID.uuid4()
      job = insert(:job)
      user_id = UUID.uuid4()
      expect_job_update(job._id, Job.status(:failed), "Episode in status closed can not be updated", 409)

      assert :ok =
               Consumer.consume(%EpisodeUpdateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: UUID.binary_to_string!(episode.id.binary),
                 request_params: %{
                   "managing_organization" => %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
                       "value" => client_id
                     }
                   },
                   "care_manager" => %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                       "value" => UUID.uuid4()
                     }
                   },
                   "name" => "ОРВИ 2019"
                 },
                 user_id: user_id,
                 client_id: client_id
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end

    test "episode was updated" do
      current_config = Application.get_env(:core, :service_request_expiration_days)
      expiration_days = 2

      on_exit(fn ->
        Application.put_env(:core, :service_request_expiration_days, current_config)
      end)

      Application.put_env(:core, :service_request_expiration_days, expiration_days)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      client_id = UUID.uuid4()

      episode =
        build(
          :episode,
          managing_organization:
            reference_coding(Mongo.string_to_uuid(client_id), %{system: "eHealth/resources", code: "legal_entity"})
        )

      episode_id = UUID.binary_to_string!(episode.id.binary)
      insert(:patient, _id: patient_id_hash, episodes: %{episode_id => episode})

      expect_doctor(client_id)

      job = insert(:job)
      user_id = UUID.uuid4()

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [
                   %{"collection" => "patients", "operation" => "update_one", "set" => updated_episode},
                   %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
                 ]
               } = Jason.decode!(args)

        updated_episode = updated_episode |> Base.decode64!() |> BSON.decode()
        assert updated_episode["$set"]["episodes.#{episode_id}.name"] == "ОРВИ 2019"

        assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

        set_bson = set |> Base.decode64!() |> BSON.decode()

        status = Job.status(:processed)

        response = %{
          "links" => [
            %{
              "entity" => "episode",
              "href" => "/api/patients/#{patient_id}/episodes/#{episode_id}"
            }
          ]
        }

        assert %{
                 "$set" => %{
                   "status" => ^status,
                   "status_code" => 200,
                   "response" => ^response
                 }
               } = set_bson

        :ok
      end)

      assert :ok =
               Consumer.consume(%EpisodeUpdateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: episode_id,
                 request_params: %{
                   "care_manager" => %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                       "value" => UUID.uuid4()
                     }
                   },
                   "name" => "ОРВИ 2019"
                 },
                 user_id: user_id,
                 client_id: client_id
               })
    end
  end
end
