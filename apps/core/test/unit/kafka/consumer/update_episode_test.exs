defmodule Core.Kafka.Consumer.UpdateEpisodeTest do
  @moduledoc false

  use Core.ModelCase

  import Mox
  import Core.Expectations.IlExpectations

  alias Core.Episode
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.EpisodeUpdateJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  alias Core.Patients.Episodes

  @status_pending Job.status(:pending)
  setup :verify_on_exit!

  describe "consume update episode event" do
    test "update with invalid status" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      episode = build(:episode, status: Episode.status(:closed))
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, episodes: %{UUID.binary_to_string!(episode.id.binary) => episode}, _id: patient_id_hash)
      client_id = UUID.uuid4()
      job = insert(:job)
      user_id = UUID.uuid4()
      expect_job_update(job._id, "Episode in status closed can not be updated", 422)

      assert :ok =
               Consumer.consume(%EpisodeUpdateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: UUID.binary_to_string!(episode.id.binary),
                 request_params: %{
                   "managing_organization" => %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
                       "value" => client_id
                     }
                   },
                   "care_manager" => %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                       "value" => UUID.uuid4()
                     }
                   },
                   "name" => "ОРВИ 2019"
                 },
                 user_id: user_id,
                 client_id: client_id
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end

    test "episode was updated" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient = insert(:patient, _id: patient_id_hash)
      episode_id = patient.episodes |> Map.keys() |> hd

      client_id =
        patient.episodes
        |> Map.values()
        |> hd
        |> Map.get(:managing_organization)
        |> Map.get(:identifier)
        |> Map.get(:value)
        |> to_string()

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
               Consumer.consume(%EpisodeUpdateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: episode_id,
                 request_params: %{
                   "care_manager" => %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                       "value" => UUID.uuid4()
                     }
                   },
                   "name" => "ОРВИ 2019"
                 },
                 user_id: user_id,
                 client_id: client_id
               })

      assert {:ok, %Episode{name: "ОРВИ 2019"}} = Episodes.get_by_id(patient_id_hash, episode_id)
      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end
  end
end
