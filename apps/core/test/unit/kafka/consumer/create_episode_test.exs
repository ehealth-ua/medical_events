defmodule Core.Kafka.Consumer.CreateEpisodeTest do
  @moduledoc false

  use Core.ModelCase

  import Mox
  import Core.Expectations.IlExpectations

  alias Core.Episode
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Kafka.Consumer
  alias Core.Mongo
  alias Core.Patient
  alias Core.Patients

  @status_pending Job.status(:pending)

  setup :verify_on_exit!

  describe "consume create episode event" do
    test "episode already exists" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient = insert(:patient, _id: patient_id_hash)
      episode_id = patient.episodes |> Map.keys() |> hd

      job = insert(:job)
      user_id = UUID.uuid4()
      client_id = UUID.uuid4()
      expect_doctor(client_id)
      expect_job_update(job._id, "Episode with such id already exists", 422)

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
                 }
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end

    test "episode was created" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

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

      expect_job_update(
        job._id,
        %{
          "links" => [
            %{
              "entity" => "episode",
              "href" => "/api/patients/#{patient_id}/episodes/#{episode_id}"
            }
          ]
        },
        200
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
                 }
               })

      assert %{"episodes" => episodes} =
               Mongo.find_one(
                 Patient.metadata().collection,
                 %{"_id" => Patients.get_pk_hash(patient_id)},
                 projection: [episodes: true]
               )

      assert Map.has_key?(episodes, episode_id)
      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end
  end
end
