defmodule Core.Kafka.Consumer.UpdateEpisodeTest do
  @moduledoc false

  use Core.ModelCase
  import Mox
  alias Core.Episode
  alias Core.Jobs
  alias Core.Jobs.EpisodeUpdateJob
  alias Core.Kafka.Consumer
  alias Core.Patients.Episodes

  describe "consume update episode event" do
    test "update with invalid status" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      episode = build(:episode, status: Episode.status(:closed))
      patient = insert(:patient, episodes: %{UUID.binary_to_string!(episode.id.binary) => episode})
      client_id = UUID.uuid4()

      stub(IlMock, :get_employee, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "APPROVED",
             "employee_type" => "DOCTOR",
             "legal_entity" => %{"id" => client_id}
           }
         }}
      end)

      job = insert(:job)
      user_id = UUID.uuid4()

      assert :ok =
               Consumer.consume(%EpisodeUpdateJob{
                 _id: to_string(job._id),
                 patient_id: patient._id,
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

      assert {:ok, %{response: "Episode in status closed can not be updated"}} = Jobs.get_by_id(to_string(job._id))
    end

    test "episode was updated" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      patient = insert(:patient)
      episode_id = patient.episodes |> Map.keys() |> hd
      client_id = UUID.uuid4()

      stub(IlMock, :get_employee, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "APPROVED",
             "employee_type" => "DOCTOR",
             "legal_entity" => %{"id" => client_id},
             "party" => %{
               "first_name" => "foo",
               "second_name" => "bar",
               "last_name" => "baz"
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

      job = insert(:job)
      user_id = UUID.uuid4()

      assert :ok =
               Consumer.consume(%EpisodeUpdateJob{
                 _id: to_string(job._id),
                 patient_id: patient._id,
                 id: episode_id,
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

      assert {:ok, %{response: %{}}} = Jobs.get_by_id(to_string(job._id))
      assert {:ok, %{"name" => "ОРВИ 2019"}} = Episodes.get(patient._id, episode_id)
    end
  end
end
