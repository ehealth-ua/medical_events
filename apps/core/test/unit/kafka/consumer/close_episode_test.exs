defmodule Core.Kafka.Consumer.CloseEpisodeTest do
  @moduledoc false

  use Core.ModelCase
  import Mox
  alias Core.Episode
  alias Core.Jobs
  alias Core.Jobs.EpisodeCloseJob
  alias Core.Kafka.Consumer
  alias Core.Patients.Episodes

  @closed Episode.status(:closed)

  describe "consume close episode event" do
    test "close with invalid status" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      episode = build(:episode, status: @closed)
      patient = insert(:patient, episodes: %{episode.id => episode})
      job = insert(:job)
      user_id = UUID.uuid4()
      client_id = UUID.uuid4()

      assert :ok =
               Consumer.consume(%EpisodeCloseJob{
                 _id: job._id,
                 patient_id: patient._id,
                 id: episode.id,
                 request_params: %{
                   "period" => %{"end" => to_string(Date.utc_today())},
                   "closing_reason" => %{
                     "coding" => [%{"code" => "legal_entity", "system" => "eHealth/episode_closing_reasons"}]
                   },
                   "closing_summary" => "summary"
                 },
                 user_id: user_id,
                 client_id: client_id
               })

      assert {:ok, %{response: "Episode in status closed can not be closed"}} = Jobs.get_by_id(job._id)
    end

    test "episode was closed" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      patient = insert(:patient)
      episode_id = patient.episodes |> Map.keys() |> hd

      job = insert(:job)
      user_id = UUID.uuid4()
      client_id = UUID.uuid4()

      assert :ok =
               Consumer.consume(%EpisodeCloseJob{
                 _id: job._id,
                 patient_id: patient._id,
                 id: episode_id,
                 request_params: %{
                   "period" => %{"end" => to_string(Date.utc_today())},
                   "closing_reason" => %{
                     "coding" => [%{"code" => "legal_entity", "system" => "eHealth/episode_closing_reasons"}]
                   },
                   "closing_summary" => "summary"
                 },
                 user_id: user_id,
                 client_id: client_id
               })

      assert {:ok, %{response: %{}}} = Jobs.get_by_id(job._id)
      assert {:ok, %{"status" => @closed}} = Episodes.get(patient._id, episode_id)
    end
  end
end
