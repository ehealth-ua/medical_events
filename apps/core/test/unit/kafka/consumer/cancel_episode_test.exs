defmodule Core.Kafka.Consumer.CancelEpisodeTest do
  @moduledoc false

  use Core.ModelCase
  import Mox
  alias Core.Episode
  alias Core.Job
  alias Core.Jobs.EpisodeCancelJob
  alias Core.Kafka.Consumer
  alias Core.Patients

  @canceled Episode.status(:cancelled)
  setup :verify_on_exit!

  describe "consume cancel episode event" do
    test "cancel with invalid status" do
      episode = build(:episode, status: @canceled)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, episodes: %{UUID.binary_to_string!(episode.id.binary) => episode}, _id: patient_id_hash)
      job = insert(:job)
      user_id = UUID.uuid4()
      client_id = UUID.uuid4()
      expect_job_update(job._id, Job.status(:failed), "Episode in status entered_in_error can not be canceled", 409)

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
    end

    test "failed when episode's managing organization is invalid" do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient = insert(:patient, _id: patient_id_hash)
      episode_id = patient.episodes |> Map.keys() |> hd

      job = insert(:job)
      user_id = UUID.uuid4()
      client_id = UUID.uuid4()

      expect_job_update(
        job._id,
        Job.status(:failed),
        "Managing_organization does not correspond to user's legal_entity",
        409
      )

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
    end

    test "episode was canceled" do
      job = insert(:job)
      user_id = UUID.uuid4()
      client_id = UUID.uuid4()

      episode =
        build(:episode, managing_organization: reference_coding(Mongo.string_to_uuid(client_id), code: "legal_entity"))

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash, episodes: %{UUID.binary_to_string!(episode.id.binary) => episode})
      episode_id = UUID.binary_to_string!(episode.id.binary)

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

        assert %{
                 "$set" => %{
                   "status" => ^status,
                   "status_code" => 200,
                   "response" => %{}
                 }
               } = set_bson

        :ok
      end)

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
    end
  end
end
