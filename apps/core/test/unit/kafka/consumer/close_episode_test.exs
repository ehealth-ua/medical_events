defmodule Core.Kafka.Consumer.CloseEpisodeTest do
  @moduledoc false

  use Core.ModelCase
  alias Core.Episode
  alias Core.Job
  alias Core.Jobs.EpisodeCloseJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  import Mox

  @closed Episode.status(:closed)
  setup :verify_on_exit!

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

      expect_job_update(job._id, Job.status(:failed), "Episode in status closed can not be closed", 422)

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
    end

    test "failed when episode's managing organization is invalid" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      job = insert(:job)
      user_id = UUID.uuid4()
      client_id = UUID.uuid4()

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

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.managing_organization.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Managing_organization does not correspond to user's legal_entity",
                  "params" => [],
                  "rule" => "invalid"
                }
              ]
            }
          ],
          "message" =>
            "Validation failed. You can find validators description at our API Manifest: http://docs.apimanifest.apiary.io/#introduction/interacting-with-api/errors.",
          "type" => "validation_failed"
        },
        422
      )

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
    end

    test "episode was closed" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_medical_event, fn _event -> :ok end)

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

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert [
                 %{"collection" => "patients", "operation" => "update_one"},
                 %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
               ] = Jason.decode!(args)

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
    end
  end
end
