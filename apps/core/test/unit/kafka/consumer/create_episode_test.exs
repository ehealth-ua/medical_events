defmodule Core.Kafka.Consumer.CreateEpisodeTest do
  @moduledoc false

  use Core.ModelCase

  import Mox

  alias Core.Kafka.Consumer
  alias Core.Mongo
  alias Core.Patient
  alias Core.Jobs
  alias Core.Jobs.EpisodeCreateJob

  describe "consume create episode event" do
    test "episode already exists" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      patient = build(:patient)
      assert {:ok, _} = Mongo.insert_one(patient)
      episode_id = patient.episodes |> Map.keys() |> hd

      job = build(:job)
      assert {:ok, _} = Mongo.insert_one(job)
      user_id = UUID.uuid4()

      assert :ok =
               Consumer.consume(%EpisodeCreateJob{
                 _id: job._id,
                 patient_id: patient._id,
                 id: episode_id,
                 user_id: user_id
               })

      error = "Episode with id #{episode_id} already exists"

      assert {:ok, %{response: %{"error" => ^error}}} = Jobs.get_by_id(job._id)
    end

    test "episode was created" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      patient = build(:patient)
      assert {:ok, _} = Mongo.insert_one(patient)
      episode_id = UUID.uuid4()

      job = build(:job)
      assert {:ok, _} = Mongo.insert_one(job)
      user_id = UUID.uuid4()

      assert :ok =
               Consumer.consume(%EpisodeCreateJob{
                 _id: job._id,
                 patient_id: patient._id,
                 id: episode_id,
                 user_id: user_id
               })

      assert %{"episodes" => episodes} =
               Mongo.find_one(Patient.metadata().collection, %{"_id" => patient._id}, projection: [episodes: true])

      assert Map.has_key?(episodes, episode_id)
      assert {:ok, %{response: %{}}} = Jobs.get_by_id(job._id)
    end
  end
end
