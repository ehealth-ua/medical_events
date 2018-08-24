defmodule Core.Kafka.Consumer.CreateEpisodeTest do
  @moduledoc false

  use Core.ModelCase

  import Mox

  alias Core.Episode
  alias Core.Jobs
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Kafka.Consumer
  alias Core.Mongo
  alias Core.Patient

  describe "consume create episode event" do
    test "episode already exists" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      patient = insert(:patient)
      episode_id = patient.episodes |> Map.keys() |> hd

      job = insert(:job)
      user_id = UUID.uuid4()
      client_id = UUID.uuid4()

      stub(IlMock, :get_employee, fn id, _ ->
        {:ok,
         %{"data" => %{"id" => id, "status" => "APPROVED", "employee_type" => "DOCTOR", "legal_entity_id" => client_id}}}
      end)

      assert :ok =
               Consumer.consume(%EpisodeCreateJob{
                 _id: job._id,
                 patient_id: patient._id,
                 id: episode_id,
                 user_id: user_id,
                 client_id: client_id,
                 managing_organization: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
                     "value" => client_id
                   }
                 },
                 period: %{"start" => DateTime.utc_now()},
                 care_manager: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => UUID.uuid4()
                   }
                 }
               })

      assert {:ok, %{response: %{"error" => "Episode with such id already exists"}}} = Jobs.get_by_id(job._id)
    end

    test "episode was created" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      patient = insert(:patient)
      episode_id = UUID.uuid4()
      client_id = UUID.uuid4()

      stub(IlMock, :get_employee, fn id, _ ->
        {:ok,
         %{"data" => %{"id" => id, "status" => "APPROVED", "employee_type" => "DOCTOR", "legal_entity_id" => client_id}}}
      end)

      job = insert(:job)
      user_id = UUID.uuid4()

      assert :ok =
               Consumer.consume(%EpisodeCreateJob{
                 _id: job._id,
                 patient_id: patient._id,
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
                 period: %{"start" => DateTime.utc_now()},
                 care_manager: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => UUID.uuid4()
                   }
                 }
               })

      assert %{"episodes" => episodes} =
               Mongo.find_one(Patient.metadata().collection, %{"_id" => patient._id}, projection: [episodes: true])

      assert Map.has_key?(episodes, episode_id)
      assert {:ok, %{response: %{}}} = Jobs.get_by_id(job._id)
    end
  end
end
