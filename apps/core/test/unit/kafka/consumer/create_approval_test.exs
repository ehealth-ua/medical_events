defmodule Core.Kafka.Consumer.CreateApprovalTest do
  @moduledoc false

  use Core.ModelCase

  alias Core.Approval
  alias Core.Job
  alias Core.Jobs.ApprovalCreateJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  alias Core.ServiceRequest

  import Mox
  import Core.Expectations.IlExpectations
  import Core.Expectations.OTPVerificationExpectations

  @approval_create_response_fields ~w(
    access_level
    expires_at
    granted_resources
    granted_to
    id
    reason
    status
    authentication_method_current
  )

  setup :verify_on_exit!

  describe "consume create approval event" do
    test "success approval create with resources request param" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      user_id = UUID.uuid4()
      client_id = UUID.uuid4()
      employee_id = UUID.uuid4()
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      episode_1 =
        build(:episode, managing_organization: reference_coding(Mongo.string_to_uuid(client_id), code: "legal_entity"))

      episode_2 = build(:episode)

      patient =
        insert(
          :patient,
          _id: patient_id_hash,
          episodes: %{
            UUID.binary_to_string!(episode_1.id.binary) => episode_1,
            UUID.binary_to_string!(episode_2.id.binary) => episode_2
          }
        )

      diagnostic_report_id = patient.diagnostic_reports |> Map.keys() |> hd()

      rpc_expectations(client_id)
      expect_employees_by_user_id_client_id([employee_id])
      expect_otp_verification_initialize()

      job = insert(:job)

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert [
                 %{"collection" => "approvals", "operation" => "insert"},
                 %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
               ] = Jason.decode!(args)

        assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

        set_bson =
          set
          |> Base.decode64!()
          |> BSON.decode()

        response_data = set_bson["$set"]["response"]["response_data"]

        Enum.each(@approval_create_response_fields, fn field ->
          assert Map.has_key?(response_data, field)
        end)

        granted_resources_ids =
          response_data["granted_resources"]
          |> Enum.map(&get_in(&1, ~w(identifier value)))
          |> Enum.map(&to_string/1)

        Enum.each([episode_1.id, episode_2.id], fn episode_id ->
          assert to_string(episode_id) in granted_resources_ids
        end)

        assert get_in(response_data, ~w(granted_to identifier value)) == employee_id
        refute get_in(response_data, ~w(reason identifier value))

        status = Job.status(:processed)

        assert %{
                 "$set" => %{
                   "status" => ^status,
                   "status_code" => 200,
                   "response" => response
                 }
               } = set_bson

        :ok
      end)

      assert :ok =
               Consumer.consume(%ApprovalCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 resources: [
                   %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
                       "value" => UUID.binary_to_string!(episode_1.id.binary)
                     }
                   },
                   %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
                       "value" => UUID.binary_to_string!(episode_2.id.binary)
                     }
                   },
                   %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                       "value" => diagnostic_report_id
                     }
                   }
                 ],
                 service_request: nil,
                 granted_to: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => employee_id
                   }
                 },
                 access_level: Approval.access_level(:read),
                 user_id: user_id,
                 client_id: client_id
               })
    end

    test "success approval create with service_request request param" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      user_id = UUID.uuid4()
      client_id = UUID.uuid4()
      employee_id = UUID.uuid4()
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      episode_1 =
        build(:episode, managing_organization: reference_coding(Mongo.string_to_uuid(client_id), code: "legal_entity"))

      episode_2 = build(:episode)

      patient =
        insert(
          :patient,
          _id: patient_id_hash,
          episodes: %{
            UUID.binary_to_string!(episode_1.id.binary) => episode_1,
            UUID.binary_to_string!(episode_2.id.binary) => episode_2
          }
        )

      diagnostic_report_id = patient.diagnostic_reports |> Map.keys() |> hd() |> Mongo.string_to_uuid()

      rpc_expectations(client_id)
      expect_employees_by_user_id_client_id([employee_id])
      expect_otp_verification_initialize()

      episodes = build_references(:episode, [episode_1.id, episode_2.id])
      diagnostic_reports = build_references(:diagnostic_report, [diagnostic_report_id])

      service_request =
        insert(:service_request, subject: patient_id_hash, permitted_resources: episodes ++ diagnostic_reports)

      service_request_id = to_string(service_request._id)

      job = insert(:job)

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert [
                 %{"collection" => "approvals", "operation" => "insert"},
                 %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
               ] = Jason.decode!(args)

        assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

        set_bson =
          set
          |> Base.decode64!()
          |> BSON.decode()

        response_data = set_bson["$set"]["response"]["response_data"]

        Enum.each(@approval_create_response_fields, fn field ->
          assert Map.has_key?(response_data, field)
        end)

        granted_resources_ids =
          response_data["granted_resources"]
          |> Enum.map(&get_in(&1, ~w(identifier value)))
          |> Enum.map(&to_string/1)

        Enum.each([episode_1.id, episode_2.id, diagnostic_report_id], fn resource_id ->
          assert to_string(resource_id) in granted_resources_ids
        end)

        assert get_in(response_data, ~w(granted_to identifier value)) == employee_id
        assert get_in(response_data, ~w(reason identifier value)) == service_request_id

        status = Job.status(:processed)

        assert %{
                 "$set" => %{
                   "status" => ^status,
                   "status_code" => 200,
                   "response" => response
                 }
               } = set_bson

        :ok
      end)

      assert :ok =
               Consumer.consume(%ApprovalCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 resources: nil,
                 service_request: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                     "value" => service_request_id
                   }
                 },
                 granted_to: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => employee_id
                   }
                 },
                 access_level: Approval.access_level(:read),
                 user_id: user_id,
                 client_id: client_id
               })
    end

    test "success approval create when person's auth method is not OTP" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      user_id = UUID.uuid4()
      client_id = UUID.uuid4()
      employee_id = UUID.uuid4()
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      episode_1 =
        build(:episode, managing_organization: reference_coding(Mongo.string_to_uuid(client_id), code: "legal_entity"))

      episode_2 = build(:episode)

      patient =
        insert(
          :patient,
          _id: patient_id_hash,
          episodes: %{
            UUID.binary_to_string!(episode_1.id.binary) => episode_1,
            UUID.binary_to_string!(episode_2.id.binary) => episode_2
          }
        )

      diagnostic_report_id = patient.diagnostic_reports |> Map.keys() |> hd()

      offline_auth_rpc_expectations(client_id)
      expect_employees_by_user_id_client_id([employee_id])

      job = insert(:job)

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert [
                 %{"collection" => "approvals", "operation" => "insert"},
                 %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
               ] = Jason.decode!(args)

        assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

        set_bson =
          set
          |> Base.decode64!()
          |> BSON.decode()

        response_data = set_bson["$set"]["response"]["response_data"]

        Enum.each(@approval_create_response_fields, fn field ->
          assert Map.has_key?(response_data, field)
        end)

        granted_resources_ids =
          response_data["granted_resources"]
          |> Enum.map(&get_in(&1, ~w(identifier value)))
          |> Enum.map(&to_string/1)

        Enum.each([episode_1.id, episode_2.id], fn episode_id ->
          assert to_string(episode_id) in granted_resources_ids
        end)

        assert get_in(response_data, ~w(granted_to identifier value)) == employee_id
        refute get_in(response_data, ~w(reason identifier value))

        status = Job.status(:processed)

        assert %{
                 "$set" => %{
                   "status" => ^status,
                   "status_code" => 200,
                   "response" => response
                 }
               } = set_bson

        :ok
      end)

      assert :ok =
               Consumer.consume(%ApprovalCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 resources: [
                   %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
                       "value" => UUID.binary_to_string!(episode_1.id.binary)
                     }
                   },
                   %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
                       "value" => UUID.binary_to_string!(episode_2.id.binary)
                     }
                   },
                   %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                       "value" => diagnostic_report_id
                     }
                   }
                 ],
                 service_request: nil,
                 granted_to: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => employee_id
                   }
                 },
                 access_level: Approval.access_level(:read),
                 user_id: user_id,
                 client_id: client_id
               })
    end

    test "failed approval create with service_request request param when service_request is not active" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      user_id = UUID.uuid4()
      client_id = UUID.uuid4()
      employee_id = UUID.uuid4()
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      episode_1 =
        build(:episode, managing_organization: reference_coding(Mongo.string_to_uuid(client_id), code: "legal_entity"))

      episode_2 = build(:episode)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{
          UUID.binary_to_string!(episode_1.id.binary) => episode_1,
          UUID.binary_to_string!(episode_2.id.binary) => episode_2
        }
      )

      episodes = build_references(:episode, [episode_1.id.binary, episode_2.id.binary])

      service_request =
        insert(:service_request,
          subject: patient_id_hash,
          permitted_resources: episodes,
          status: ServiceRequest.status(:recalled)
        )

      service_request_id = to_string(service_request._id)

      job = insert(:job)
      expect_job_update(job._id, Job.status(:failed), "Service request should be active", 409)

      assert :ok =
               Consumer.consume(%ApprovalCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 resources: nil,
                 service_request: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                     "value" => service_request_id
                   }
                 },
                 granted_to: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => employee_id
                   }
                 },
                 access_level: Approval.access_level(:read),
                 user_id: user_id,
                 client_id: client_id
               })
    end

    test "failed approval create with service_request request param when service_request expiration_date is invalid" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      current_config = Application.get_env(:core, :service_request_expiration_days)
      expiration_days = 2

      on_exit(fn ->
        Application.put_env(:core, :service_request_expiration_days, current_config)
      end)

      Application.put_env(:core, :service_request_expiration_days, expiration_days)

      user_id = UUID.uuid4()
      client_id = UUID.uuid4()
      employee_id = UUID.uuid4()
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      now = DateTime.utc_now()

      episode_1 =
        build(:episode, managing_organization: reference_coding(Mongo.string_to_uuid(client_id), code: "legal_entity"))

      episode_2 = build(:episode)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{
          UUID.binary_to_string!(episode_1.id.binary) => episode_1,
          UUID.binary_to_string!(episode_2.id.binary) => episode_2
        }
      )

      episodes = build_references(:episode, [episode_1.id.binary, episode_2.id.binary])

      service_request =
        insert(:service_request,
          subject: patient_id_hash,
          permitted_resources: episodes,
          inserted_at: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * (expiration_days + 1)),
          expiration_date: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * expiration_days)
        )

      service_request_id = to_string(service_request._id)

      job = insert(:job)

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert [
                 %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
               ] = Jason.decode!(args)

        assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

        set_bson = set |> Base.decode64!() |> BSON.decode()
        status = Job.status(:failed)

        assert %{
                 "$set" => %{
                   "status" => ^status,
                   "status_code" => 422,
                   "response" => %{
                     "invalid" => [
                       %{
                         "entry" => "$.service_request",
                         "entry_type" => "json_data_property",
                         "rules" => [
                           %{
                             "description" =>
                               "Service request expiration date must be a datetime greater than or equal" <> _,
                             "params" => [],
                             "rule" => "invalid"
                           }
                         ]
                       }
                     ]
                   }
                 }
               } = set_bson

        :ok
      end)

      assert :ok =
               Consumer.consume(%ApprovalCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 resources: nil,
                 service_request: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                     "value" => service_request_id
                   }
                 },
                 granted_to: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => employee_id
                   }
                 },
                 access_level: Approval.access_level(:read),
                 user_id: user_id,
                 client_id: client_id
               })
    end

    test "failed approval create with service_request request param when service_request does not contain episode references" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      user_id = UUID.uuid4()
      client_id = UUID.uuid4()
      employee_id = UUID.uuid4()
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      service_request = insert(:service_request, subject: patient_id_hash, permitted_resources: nil)
      service_request_id = to_string(service_request._id)

      job = insert(:job)
      expect_job_update(job._id, Job.status(:failed), "Service request does not contain resources references", 409)

      assert :ok =
               Consumer.consume(%ApprovalCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 resources: nil,
                 service_request: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                     "value" => service_request_id
                   }
                 },
                 granted_to: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => employee_id
                   }
                 },
                 access_level: Approval.access_level(:read),
                 user_id: user_id,
                 client_id: client_id
               })
    end

    test "failed approval create with service_request request param when service_request is not found" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      user_id = UUID.uuid4()
      client_id = UUID.uuid4()
      employee_id = UUID.uuid4()
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      job = insert(:job)
      expect_job_update(job._id, Job.status(:failed), "Service request is not found", 409)

      assert :ok =
               Consumer.consume(%ApprovalCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 resources: nil,
                 service_request: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                     "value" => UUID.uuid4()
                   }
                 },
                 granted_to: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => employee_id
                   }
                 },
                 access_level: Approval.access_level(:read),
                 user_id: user_id,
                 client_id: client_id
               })
    end

    test "failed approval create when granted_to and granted_resources params are invalid" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      user_id = UUID.uuid4()
      client_id = UUID.uuid4()
      employee_id = UUID.uuid4()
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      episode = build(:episode)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode}
      )

      rpc_expectations(client_id)
      expect_employees_by_user_id_client_id([UUID.uuid4()])

      job = insert(:job)

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.granted_resources.[1].identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Episode with such ID is not found",
                  "params" => [],
                  "rule" => "invalid"
                }
              ]
            },
            %{
              "entry" => "$.granted_resources.[2].identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Diagnostic report with such id is not found",
                  "params" => [],
                  "rule" => "invalid"
                }
              ]
            },
            %{
              "entry" => "$.granted_to.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Employee does not related to user",
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
               Consumer.consume(%ApprovalCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 resources: [
                   %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
                       "value" => UUID.binary_to_string!(episode.id.binary)
                     }
                   },
                   %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
                       "value" => UUID.uuid4()
                     }
                   },
                   %{
                     "identifier" => %{
                       "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                       "value" => UUID.uuid4()
                     }
                   }
                 ],
                 service_request: nil,
                 granted_to: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => employee_id
                   }
                 },
                 access_level: Approval.access_level(:read),
                 user_id: user_id,
                 client_id: client_id
               })
    end
  end

  defp build_references(type, entity_ids) when is_list(entity_ids) do
    code =
      case type do
        :episode -> "episode_of_care"
        :diagnostic_report -> "diagnostic_report"
        _ -> "undefined"
      end

    Enum.map(entity_ids, fn entity_id ->
      build(:reference,
        identifier:
          build(:identifier,
            value: entity_id,
            type: codeable_concept_coding(system: "eHealth/resources", code: code)
          )
      )
    end)
  end

  defp rpc_expectations(client_id) do
    expect(WorkerMock, :run, 2, fn
      _, _, :get_auth_method, _ ->
        {:ok, %{"type" => "OTP", "phone_number" => "+38#{Enum.random(1_000_000_000..9_999_999_999)}"}}

      _, _, :employee_by_id, [id] ->
        %{
          id: id,
          status: "APPROVED",
          employee_type: "DOCTOR",
          legal_entity_id: client_id,
          party: %{
            first_name: "foo",
            second_name: "bar",
            last_name: "baz"
          }
        }
    end)
  end

  defp offline_auth_rpc_expectations(client_id) do
    expect(WorkerMock, :run, 2, fn
      _, _, :employee_by_id, [id] ->
        %{
          id: id,
          status: "APPROVED",
          employee_type: "DOCTOR",
          legal_entity_id: client_id,
          party: %{
            first_name: "foo",
            second_name: "bar",
            last_name: "baz"
          }
        }

      _, _, :get_auth_method, _ ->
        {:ok, %{"type" => "OFFLINE"}}
    end)
  end
end
