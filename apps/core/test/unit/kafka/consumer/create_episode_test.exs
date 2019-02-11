defmodule Core.Kafka.Consumer.CreateEpisodeTest do
  @moduledoc false

  use Core.ModelCase

  import Mox
  import Core.Expectations.IlExpectations

  alias Core.Episode
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Kafka.Consumer
  alias Core.Mongo
  alias Core.Patient
  alias Core.Patients

  @status_pending Job.status(:pending)

  setup :verify_on_exit!

  describe "consume create episode event" do
    test "episode already exists" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient = insert(:patient, _id: patient_id_hash)
      episode_id = patient.episodes |> Map.keys() |> hd

      job = insert(:job)
      user_id = UUID.uuid4()
      client_id = UUID.uuid4()
      expect_doctor(client_id)
      expect_job_update(job._id, "Episode with such id already exists", 422)

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

      assert :ok =
               Consumer.consume(%EpisodeCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: episode_id,
                 type: %{"code" => "primary_care", "system" => "eHealth/episode_types"},
                 user_id: user_id,
                 client_id: client_id,
                 managing_organization: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
                     "value" => client_id
                   }
                 },
                 period: %{"start" => to_string(Date.utc_today())},
                 care_manager: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => UUID.uuid4()
                   }
                 }
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end

    test "episode was created" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      episode_id = UUID.uuid4()
      client_id = UUID.uuid4()
      expect_doctor(client_id, 2)

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

      service_request = insert(:service_request, used_by: build(:reference))

      assert :ok =
               Consumer.consume(%EpisodeCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: episode_id,
                 type: %{"code" => "primary_care", "system" => "eHealth/episode_types"},
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
                 period: %{"start" => to_string(Date.utc_today())},
                 care_manager: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => UUID.uuid4()
                   }
                 },
                 referral_requests: [
                   %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                       "value" => to_string(service_request._id)
                     }
                   }
                 ]
               })

      assert %{"episodes" => episodes} =
               Mongo.find_one(
                 Patient.metadata().collection,
                 %{"_id" => Patients.get_pk_hash(patient_id)},
                 projection: [episodes: true]
               )

      assert Map.has_key?(episodes, episode_id)
      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end

    test "fail on invalid referral_request's expiration_date" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      current_config = Application.get_env(:core, :service_request_expiration_days)
      expiration_days = 2

      on_exit(fn ->
        Application.put_env(:core, :service_request_expiration_days, current_config)
      end)

      Application.put_env(:core, :service_request_expiration_days, expiration_days)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      episode_id = UUID.uuid4()
      client_id = UUID.uuid4()
      expect_doctor(client_id, 3)

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
      now = DateTime.utc_now()

      expect_job_update(
        job._id,
        %{
          invalid: [
            %{
              entry: "$.referral_requests.[1].identifier.value",
              entry_type: "json_data_property",
              rules: [
                %{
                  description: "Service request expiration date must be a datetime greater than or equal",
                  params: [],
                  rule: :invalid
                }
              ]
            }
          ],
          message:
            "Validation failed. You can find validators description at our API Manifest: http://docs.apimanifest.apiary.io/#introduction/interacting-with-api/errors.",
          type: :validation_failed
        },
        422
      )

      service_request_in = insert(:service_request, used_by: build(:reference))

      service_request_out =
        insert(:service_request,
          used_by: build(:reference),
          inserted_at: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * (expiration_days + 1)),
          expiration_date: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * expiration_days)
        )

      assert :ok =
               Consumer.consume(%EpisodeCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: episode_id,
                 type: %{"code" => "primary_care", "system" => "eHealth/episode_types"},
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
                 period: %{"start" => to_string(Date.utc_today())},
                 care_manager: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => UUID.uuid4()
                   }
                 },
                 referral_requests: [
                   %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                       "value" => to_string(service_request_in._id)
                     }
                   },
                   %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                       "value" => to_string(service_request_out._id)
                     }
                   }
                 ]
               })

      assert %{"episodes" => episodes} =
               Mongo.find_one(
                 Patient.metadata().collection,
                 %{"_id" => Patients.get_pk_hash(patient_id)},
                 projection: [episodes: true]
               )

      refute Map.has_key?(episodes, episode_id)
      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end
  end
end
