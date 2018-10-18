defmodule Core.Kafka.Consumer.CloseEpisodeTest do
  @moduledoc false

  use Core.ModelCase
  import Mox
  alias Core.Episode
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.EpisodeCloseJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  alias Core.Patients.Episodes

  @closed Episode.status(:closed)
  @status_processed Job.status(:processed)

  describe "consume close episode event" do
    test "close with invalid status" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      episode = build(:episode, status: @closed)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, episodes: %{UUID.binary_to_string!(episode.id.binary) => episode}, _id: patient_id_hash)
      job = insert(:job)
      user_id = UUID.uuid4()
      client_id = UUID.uuid4()

      assert :ok =
               Consumer.consume(%EpisodeCloseJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: UUID.binary_to_string!(episode.id.binary),
                 request_params: %{
                   "period" => %{"end" => to_string(Date.utc_today())},
                   "status_reason" => %{
                     "coding" => [%{"code" => "legal_entity", "system" => "eHealth/episode_closing_reasons"}]
                   },
                   "closing_summary" => "summary"
                 },
                 user_id: user_id,
                 client_id: client_id
               })

      assert {:ok, %{response: "Episode in status closed can not be closed"}} = Jobs.get_by_id(to_string(job._id))
    end

    test "failed when episode's managing organization is invalid" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      job = insert(:job)
      user_id = UUID.uuid4()
      client_id = UUID.uuid4()

      expect(IlMock, :get_employee, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "APPROVED",
             "employee_type" => "DOCTOR",
             "legal_entity" => %{"id" => client_id},
             "party" => %{
               "first_name" => "foo",
               "last_name" => "bar",
               "second_name" => "baz"
             }
           }
         }}
      end)

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

      assert :ok =
               Consumer.consume(%EpisodeCloseJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: episode_id,
                 request_params: %{
                   "period" => %{"end" => to_string(Date.utc_today())},
                   "status_reason" => %{
                     "coding" => [%{"code" => "legal_entity", "system" => "eHealth/episode_closing_reasons"}]
                   },
                   "closing_summary" => "summary"
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

    test "episode was closed" do
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
               Consumer.consume(%EpisodeCloseJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: episode_id,
                 request_params: %{
                   "period" => %{"end" => to_string(Date.utc_today())},
                   "status_reason" => %{
                     "coding" => [%{"code" => "legal_entity", "system" => "eHealth/episode_closing_reasons"}]
                   },
                   "closing_summary" => "summary"
                 },
                 user_id: user_id,
                 client_id: client_id
               })

      assert {:ok, %{response: %{}}} = Jobs.get_by_id(to_string(job._id))
      assert {:ok, %Episode{status: @closed}} = Episodes.get(patient_id_hash, episode_id)
    end
  end
end
