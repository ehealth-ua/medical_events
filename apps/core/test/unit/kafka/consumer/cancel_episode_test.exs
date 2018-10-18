defmodule Core.Kafka.Consumer.CancelEpisodeTest do
  @moduledoc false

  use Core.ModelCase
  import Mox
  alias Core.Episode
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.EpisodeCancelJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  alias Core.Patients.Episodes

  @canceled Episode.status(:cancelled)
  @status_processed Job.status(:processed)

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

    test "failed when episode's managing organization is invalid" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

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

      assert {:ok,
              %{
                response: %{
                  "invalid" => [
                    %{
                      "entry" => "$.managing_organization.identifier.value",
                      "entry_type" => "json_data_property",
                      "rules" => [
                        %{
                          "description" =>
                            "User is not allowed to perform actions with an episode that belongs to another legal entity",
                          "params" => [],
                          "rule" => "invalid"
                        }
                      ]
                    }
                  ]
                },
                status: @status_processed,
                status_code: 422
              }} = Jobs.get_by_id(to_string(job._id))
    end

    test "episode was canceled" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

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
      client_id = UUID.uuid4()

      episode =
        build(:episode, managing_organization: reference_coding(Mongo.string_to_uuid(client_id), code: "legal_entity"))

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, episodes: %{UUID.binary_to_string!(episode.id.binary) => episode})

      episode_id = UUID.binary_to_string!(episode.id.binary)

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
      assert {:ok, %Episode{status: @canceled}} = Episodes.get(patient_id_hash, episode_id)
    end
  end
end
