defmodule Core.Kafka.Consumer.CreateEpisodeTest do
  @moduledoc false

  use Core.ModelCase

  import Mox
  import Core.Expectations.IlExpectations

  alias Core.Episode
  alias Core.Jobs
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Kafka.Consumer
  alias Core.Mongo
  alias Core.Patient
  alias Core.Patients

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

      assert {:ok, %{response: %{"error" => "Episode with such id already exists"}}} =
               Jobs.get_by_id(to_string(job._id))
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

      assert :ok =
               Consumer.consume(%EpisodeCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: episode_id,
                 type: "primary_care",
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
               Mongo.find_one(Patient.metadata().collection, %{"_id" => Patients.get_pk_hash(patient_id)},
                 projection: [episodes: true]
               )

      assert Map.has_key?(episodes, episode_id)
      assert {:ok, %{response: %{}}} = Jobs.get_by_id(to_string(job._id))
    end
  end
end
