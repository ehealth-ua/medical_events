defmodule Core.Kafka.Consumer.CancelEpisodeTest do
  @moduledoc false

  use Core.ModelCase
  import Mox
  alias Core.Episode
  alias Core.Jobs
  alias Core.Jobs.EpisodeCancelJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  alias Core.Patients.Episodes

  @canceled Episode.status(:cancelled)

  describe "consume cancel episode event" do
    test "cancel with invalid status" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      episode = build(:episode, status: @canceled)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, episodes: %{UUID.binary_to_string!(episode.id.binary) => episode}, _id: patient_id_hash)
      job = insert(:job)
      user_id = UUID.uuid4()
      client_id = UUID.uuid4()

      assert :ok =
               Consumer.consume(%EpisodeCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: UUID.binary_to_string!(episode.id.binary),
                 request_params: %{
                   "status_reason" => %{
                     "coding" => [%{"code" => "misspelling", "system" => "eHealth/cancellation_reasons"}]
                   },
                   "explanatory_letter" => "Епізод був відмінений у зв'язку з помилкою при виборі пацієнта"
                 },
                 user_id: user_id,
                 client_id: client_id
               })

      assert {:ok, %{response: "Episode in status entered_in_error can not be canceled"}} =
               Jobs.get_by_id(to_string(job._id))
    end

    test "episode was canceled" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient = insert(:patient, _id: patient_id_hash)
      episode_id = patient.episodes |> Map.keys() |> hd

      job = insert(:job)
      user_id = UUID.uuid4()
      client_id = UUID.uuid4()

      assert :ok =
               Consumer.consume(%EpisodeCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: episode_id,
                 request_params: %{
                   "status_reason" => %{
                     "coding" => [%{"code" => "misspelling", "system" => "eHealth/cancellation_reasons"}]
                   },
                   "explanatory_letter" => "Епізод був відмінений у зв'язку з помилкою при виборі пацієнта"
                 },
                 user_id: user_id,
                 client_id: client_id
               })

      assert {:ok, %{response: %{}}} = Jobs.get_by_id(to_string(job._id))
      assert {:ok, %{"status" => @canceled}} = Episodes.get(patient_id_hash, episode_id)
    end
  end
end
