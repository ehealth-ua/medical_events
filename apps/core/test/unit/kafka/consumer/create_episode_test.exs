defmodule Core.Kafka.Consumer.CreateEpisodeTest do
  @moduledoc false

  use Core.ModelCase

  alias Core.Episode
  alias Core.Job
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Kafka.Consumer
  alias Core.Patients

  import Mox
  import Core.Expectations.IlExpectations

  setup :verify_on_exit!

  describe "consume create episode event" do
    test "episode already exists" do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient = insert(:patient, _id: patient_id_hash)
      episode_id = patient.episodes |> Map.keys() |> hd

      job = insert(:job)
      user_id = UUID.uuid4()
      client_id = UUID.uuid4()
      expect_doctor(client_id)
      expect_job_update(job._id, Job.status(:failed), "Episode with such id already exists", 422)

      stub(IlMock, :get_legal_entity, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "ACTIVE",
             "public_name" => "LegalEntity 1"
           }
         }}
      end)

      assert :ok =
               Consumer.consume(%EpisodeCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: episode_id,
                 name: "Хвороба",
                 type: %{"code" => "primary_care", "system" => "eHealth/episode_types"},
                 user_id: user_id,
                 client_id: client_id,
                 managing_organization: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
                     "value" => client_id
                   }
                 },
                 period: %{"start" => to_string(Date.utc_today())},
                 care_manager: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => UUID.uuid4()
                   }
                 },
                 status: Episode.status(:active)
               })
    end

    test "episode was created" do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      episode_id = UUID.uuid4()
      client_id = UUID.uuid4()
      expect_doctor(client_id)

      stub(IlMock, :get_legal_entity, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "ACTIVE",
             "public_name" => "LegalEntity 1"
           }
         }}
      end)

      job = insert(:job)
      user_id = UUID.uuid4()

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [
                   %{"collection" => "patients", "operation" => "update_one"},
                   %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
                 ]
               } = Jason.decode!(args)

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

      service_request =
        insert(:service_request,
          used_by_employee: build(:reference),
          used_by_legal_entity:
            build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(client_id)))
        )

      assert :ok =
               Consumer.consume(%EpisodeCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: episode_id,
                 type: %{"code" => "primary_care", "system" => "eHealth/episode_types"},
                 name: "ОРВИ 2018",
                 status: Episode.status(:active),
                 user_id: user_id,
                 client_id: client_id,
                 managing_organization: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
                     "value" => client_id
                   }
                 },
                 period: %{"start" => to_string(Date.utc_today())},
                 care_manager: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => UUID.uuid4()
                   }
                 },
                 referral_requests: [
                   %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                       "value" => to_string(service_request._id)
                     }
                   }
                 ]
               })
    end

    test "does not process job that was already processed" do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient = insert(:patient, _id: patient_id_hash)
      episode_id = patient.episodes |> Map.keys() |> hd

      job = insert(:job, status: Job.status(:processed))
      user_id = UUID.uuid4()
      client_id = UUID.uuid4()

      expect(WorkerMock, :run, 0, fn _, _, :transaction, _ -> :ok end)

      assert :ok =
               Consumer.consume(%EpisodeCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: episode_id,
                 user_id: user_id,
                 client_id: client_id
               })
    end
  end
end
