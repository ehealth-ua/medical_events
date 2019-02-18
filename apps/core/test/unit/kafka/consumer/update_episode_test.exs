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
      expect_job_update(job._id, Job.status(:failed), "Episode in status closed can not be updated", 422)

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

      current_config = Application.get_env(:core, :service_request_expiration_days)
      expiration_days = 2

      on_exit(fn ->
        Application.put_env(:core, :service_request_expiration_days, current_config)
      end)

      Application.put_env(:core, :service_request_expiration_days, expiration_days)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      client_id = UUID.uuid4()
      now = DateTime.utc_now()

      service_request_prev_1 =
        insert(:service_request,
          used_by: build(:reference),
          inserted_at: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * (expiration_days + 1)),
          expiration_date: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * expiration_days)
        )

      service_request_prev_2 =
        insert(:service_request,
          used_by: build(:reference),
          inserted_at: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * (expiration_days + 1)),
          expiration_date: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * expiration_days)
        )

      service_request_prev_3 =
        insert(:service_request,
          used_by: build(:reference),
          inserted_at: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * (expiration_days + 1)),
          expiration_date: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * expiration_days)
        )

      service_request_upd_1 = insert(:service_request, used_by: build(:reference))
      service_request_upd_2 = insert(:service_request, used_by: build(:reference))

      episode =
        build(
          :episode,
          managing_organization:
            reference_coding(Mongo.string_to_uuid(client_id), %{system: "eHealth/resources", code: "legal_entity"}),
          referral_requests: [
            reference_coding(service_request_prev_1._id, %{system: "eHealth/resources", code: "service_request"}),
            reference_coding(service_request_prev_2._id, %{system: "eHealth/resources", code: "service_request"}),
            reference_coding(service_request_prev_3._id, %{system: "eHealth/resources", code: "service_request"})
          ]
        )

      episode_id = UUID.binary_to_string!(episode.id.binary)
      insert(:patient, _id: patient_id_hash, episodes: %{episode_id => episode})

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

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert [
                 %{"collection" => "patients", "operation" => "update_one", "set" => updated_episode},
                 %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
               ] = Jason.decode!(args)

        updated_episode = updated_episode |> Base.decode64!() |> BSON.decode()
        assert updated_episode["$set"]["episodes.#{episode_id}.name"] == "ОРВИ 2019"

        referral_requests_ids =
          Enum.map(updated_episode["$set"]["episodes.#{episode_id}.referral_requests"], fn referral_request ->
            get_in(referral_request, ~w(identifier value))
          end)

        Enum.each(
          [service_request_prev_2._id, service_request_upd_1._id, service_request_upd_2._id],
          fn referral_request_id ->
            assert referral_request_id in referral_requests_ids
          end
        )

        Enum.each([service_request_prev_1._id, service_request_prev_3._id], fn referral_request_id ->
          refute referral_request_id in referral_requests_ids
        end)

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
                   "referral_requests" => [
                     %{
                       "identifier" => %{
                         "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                         "value" => to_string(service_request_prev_2._id)
                       }
                     },
                     %{
                       "identifier" => %{
                         "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                         "value" => to_string(service_request_upd_1._id)
                       }
                     },
                     %{
                       "identifier" => %{
                         "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                         "value" => to_string(service_request_upd_2._id)
                       }
                     }
                   ],
                   "name" => "ОРВИ 2019"
                 },
                 user_id: user_id,
                 client_id: client_id
               })
    end

    test "failed when additional referral_request is invalid" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      current_config = Application.get_env(:core, :service_request_expiration_days)
      expiration_days = 2

      on_exit(fn ->
        Application.put_env(:core, :service_request_expiration_days, current_config)
      end)

      Application.put_env(:core, :service_request_expiration_days, expiration_days)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      client_id = UUID.uuid4()
      now = DateTime.utc_now()

      service_request_prev_1 =
        insert(:service_request,
          used_by: build(:reference),
          inserted_at: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * (expiration_days + 1)),
          expiration_date: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * expiration_days)
        )

      service_request_prev_2 =
        insert(:service_request,
          used_by: build(:reference),
          inserted_at: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * (expiration_days + 1)),
          expiration_date: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * expiration_days)
        )

      service_request_prev_3 =
        insert(:service_request,
          used_by: build(:reference),
          inserted_at: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * (expiration_days + 1)),
          expiration_date: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * expiration_days)
        )

      service_request_upd_1 = insert(:service_request, used_by: build(:reference))

      service_request_upd_2 =
        insert(:service_request,
          used_by: build(:reference),
          inserted_at: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * (expiration_days + 1)),
          expiration_date: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * expiration_days)
        )

      episode =
        build(
          :episode,
          managing_organization:
            reference_coding(Mongo.string_to_uuid(client_id), %{system: "eHealth/resources", code: "legal_entity"}),
          referral_requests: [
            reference_coding(service_request_prev_1._id, %{system: "eHealth/resources", code: "service_request"}),
            reference_coding(service_request_prev_2._id, %{system: "eHealth/resources", code: "service_request"}),
            reference_coding(service_request_prev_3._id, %{system: "eHealth/resources", code: "service_request"})
          ]
        )

      episode_id = UUID.binary_to_string!(episode.id.binary)
      insert(:patient, _id: patient_id_hash, episodes: %{episode_id => episode})

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

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.referral_requests.[2].identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Service request expiration date must be a datetime greater than or equal",
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
                   "referral_requests" => [
                     %{
                       "identifier" => %{
                         "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                         "value" => to_string(service_request_prev_2._id)
                       }
                     },
                     %{
                       "identifier" => %{
                         "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                         "value" => to_string(service_request_upd_1._id)
                       }
                     },
                     %{
                       "identifier" => %{
                         "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                         "value" => to_string(service_request_upd_2._id)
                       }
                     }
                   ],
                   "name" => "ОРВИ 2019"
                 },
                 user_id: user_id,
                 client_id: client_id
               })

      assert {:ok, %Episode{} = episode} = Episodes.get_by_id(patient_id_hash, episode_id)

      referral_requests_ids =
        Enum.map(episode.referral_requests, fn referral_request ->
          referral_request.identifier.value
        end)

      Enum.each(
        [service_request_prev_1._id, service_request_prev_2._id, service_request_prev_3._id],
        fn referral_request_id ->
          assert referral_request_id in referral_requests_ids
        end
      )

      Enum.each([service_request_upd_1._id, service_request_upd_2._id], fn referral_request_id ->
        refute referral_request_id in referral_requests_ids
      end)

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end
  end
end
