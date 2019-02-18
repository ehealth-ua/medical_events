defmodule Core.Kafka.Consumer.CreateServiceRequestTest do
  @moduledoc false

  use Core.ModelCase

  alias Core.Job
  alias Core.Jobs.ServiceRequestCreateJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  alias Core.ServiceRequest

  import Core.Expectations.DigitalSignatureExpectation
  import Mox

  setup :verify_on_exit!

  describe "consume create service_request event" do
    test "empty content" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      job = insert(:job)
      user_id = prepare_signature_expectations()

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "type mismatch. Expected Object but got String",
                  "params" => ["object"],
                  "rule" => "cast"
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
               Consumer.consume(%ServiceRequestCreateJob{
                 _id: to_string(job._id),
                 signed_data: Base.encode64(""),
                 user_id: user_id,
                 client_id: UUID.uuid4()
               })
    end

    test "empty map" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      job = insert(:job)
      user_id = prepare_signature_expectations()

      response = %{
        "invalid" => [
          %{
            "entry" => "$.status",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property status was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.intent",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property intent was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.category",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property category was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.code",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property code was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.context",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property context was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.authored_on",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property authored_on was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.requester",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property requester was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          }
        ],
        "message" =>
          "Validation failed. You can find validators description at our API Manifest: http://docs.apimanifest.apiary.io/#introduction/interacting-with-api/errors.",
        "type" => "validation_failed"
      }

      expect_job_update(
        job._id,
        Job.status(:failed),
        response,
        422
      )

      assert :ok =
               Consumer.consume(%ServiceRequestCreateJob{
                 _id: to_string(job._id),
                 signed_data: Base.encode64(Jason.encode!(%{})),
                 user_id: user_id,
                 client_id: UUID.uuid4()
               })
    end

    test "success create service_request" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      expect(MediaStorageMock, :save, fn _, _, _, _ -> :ok end)
      client_id = UUID.uuid4()
      user_id = prepare_signature_expectations()
      job = insert(:job)

      employee_id = UUID.uuid4()

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      patient = insert(:patient, _id: patient_id_hash)
      encounter_id = patient.encounters |> Map.keys() |> hd()
      episode_id = patient.episodes |> Map.keys() |> hd()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      expect(WorkerMock, :run, 4, fn
        _, _, :employees_by_user_id_client_id, _ ->
          {:ok, [employee_id]}

        _, _, :tax_id_by_employee_id, _ ->
          "1111111111"

        _, _, :number, _ ->
          {:ok, UUID.uuid4()}

        _, _, :transaction, args ->
          assert [
                   %{"collection" => "service_requests", "operation" => "insert"},
                   %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
                 ] = Jason.decode!(args)

          assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

          set_bson = set |> Base.decode64!() |> BSON.decode()
          status = Job.status(:processed)

          assert %{
                   "$set" => %{
                     "status" => ^status,
                     "status_code" => 200,
                     "response" => %{
                       "links" => [
                         %{
                           "entity" => "service_request"
                         }
                       ]
                     }
                   }
                 } = set_bson

          :ok
      end)

      signed_content = %{
        "status" => ServiceRequest.status(:active),
        "intent" => ServiceRequest.intent(:order),
        "category" => %{
          "coding" => [%{"code" => "409063005", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{"coding" => [%{"code" => "128004", "system" => "eHealth/SNOMED/procedure_codes"}]},
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "performer_type" => %{
          "coding" => [%{"code" => "psychiatrist", "system" => "eHealth/SNOMED/service_request_performer_roles"}]
        },
        "supporting_info" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          }
        ],
        "permitted_episodes" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          }
        ]
      }

      assert :ok =
               Consumer.consume(%ServiceRequestCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end

    test "fail on invalid drfo" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      user_id = prepare_signature_expectations()
      job = insert(:job)

      employee_id = UUID.uuid4()

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      patient = insert(:patient, _id: patient_id_hash)
      encounter_id = patient.encounters |> Map.keys() |> hd()
      episode_id = patient.episodes |> Map.keys() |> hd()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      expect(WorkerMock, :run, 3, fn
        _, _, :employees_by_user_id_client_id, _ -> {:ok, [employee_id]}
        _, _, :tax_id_by_employee_id, _ -> "1111111112"
        _, _, :number, _ -> {:ok, UUID.uuid4()}
      end)

      signed_content = %{
        "status" => ServiceRequest.status(:active),
        "intent" => ServiceRequest.intent(:order),
        "category" => %{
          "coding" => [%{"code" => "409063005", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{"coding" => [%{"code" => "128004", "system" => "eHealth/SNOMED/procedure_codes"}]},
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "performer_type" => %{
          "coding" => [%{"code" => "psychiatrist", "system" => "eHealth/SNOMED/service_request_performer_roles"}]
        },
        "supporting_info" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          }
        ],
        "permitted_episodes" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          }
        ]
      }

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.service_request.requester.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Signer DRFO doesn't match with requester tax_id",
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
               Consumer.consume(%ServiceRequestCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end
  end

  defp prepare_signature_expectations do
    user_id = UUID.uuid4()
    drfo = "1111111111"
    expect_signature(drfo)

    user_id
  end
end
