defmodule Core.Kafka.Consumer.CancelServiceRequestTest do
  @moduledoc false

  use Core.ModelCase
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.ServiceRequestCancelJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  alias Core.Reference
  alias Core.ReferenceView
  import Core.Expectations.DigitalSignatureExpectation
  import Core.Expectations.OTPVerificationExpectations
  import Mox

  @status_pending Job.status(:pending)

  setup :verify_on_exit!

  describe "consume cancel service_request event" do
    test "empty content" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      job = insert(:job)
      user_id = prepare_signature_expectations()

      response = %{
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
      }

      expect_job_update(job._id, Job.status(:failed), response, 422)

      assert :ok =
               Consumer.consume(%ServiceRequestCancelJob{
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
            "entry" => "$.id",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property id was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
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
          },
          %{
            "entry" => "$.status_reason",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property status_reason was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.expiration_date",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property expiration_date was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.note",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property note was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.patient_instruction",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property patient_instruction was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.permitted_episodes",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property permitted_episodes was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.reason_reference",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property reason_reference was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.requisition",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property requisition was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.status_history",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property status_history was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.used_by",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property used_by was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.patient",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property patient was not present",
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

      expect_job_update(job._id, Job.status(:failed), response, 422)

      assert :ok =
               Consumer.consume(%ServiceRequestCancelJob{
                 _id: to_string(job._id),
                 signed_data: Base.encode64(Jason.encode!(%{})),
                 user_id: user_id,
                 client_id: UUID.uuid4()
               })
    end

    test "compare with db failed on cancel service_request" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      user_id = prepare_signature_expectations()
      job = insert(:job)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      service_request = insert(:service_request, subject: patient_id_hash)
      %BSON.Binary{binary: id} = service_request._id
      service_request_id = UUID.binary_to_string!(id)
      insert(:patient, _id: patient_id_hash)

      signed_content =
        %{
          "id" => service_request_id,
          "status" => service_request.status,
          "intent" => service_request.intent,
          "category" => ReferenceView.render(service_request.category),
          "code" => ReferenceView.render(service_request.code),
          "context" => ReferenceView.render(service_request.context),
          "authored_on" => service_request.authored_on,
          "requester" => ReferenceView.render(service_request.requester),
          "performer_type" => ReferenceView.render(service_request.performer_type),
          "status_reason" => %{"coding" => [%{"system" => "eHealth/service_request_cancel_reasons", "code" => "1"}]},
          "note" => "invalid",
          "expiration_date" => service_request.expiration_date,
          "patient_instruction" => service_request.patient_instruction,
          "permitted_episodes" => service_request.permitted_episodes,
          "reason_reference" => service_request.reason_reference,
          "requisition" => service_request.requisition,
          "status_history" => ReferenceView.render(service_request.status_history),
          "used_by" => ReferenceView.render(service_request.used_by),
          "supporting_info" => ReferenceView.render(service_request.supporting_info),
          "patient" =>
            ReferenceView.render(
              Reference.create(%{
                "identifier" => %{
                  "type" => %{"coding" => [%{"system" => "eHealth/resources", "code" => "patient"}], "text" => ""},
                  "value" => patient_id
                }
              })
            )
        }
        |> Map.merge(ReferenceView.render_occurrence(service_request.occurrence))

      expect_job_update(
        job._id,
        Job.status(:failed),
        "Signed content doesn't match with previously created service request",
        422
      )

      assert :ok =
               Consumer.consume(%ServiceRequestCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end

    test "success cancel service_request" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      expect(MediaStorageMock, :save, fn _, _, _, _ -> :ok end)
      client_id = UUID.uuid4()
      user_id = prepare_signature_expectations()
      job = insert(:job)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      service_request = insert(:service_request, subject: patient_id_hash)
      %BSON.Binary{binary: id} = service_request._id
      service_request_id = UUID.binary_to_string!(id)
      insert(:patient, _id: patient_id_hash)
      employee_id = to_string(service_request.requester.identifier.value)

      expect_otp_verification_send_sms()

      expect(WorkerMock, :run, 3, fn
        _, _, :employees_by_user_id_client_id, _ -> {:ok, [employee_id]}
        _, _, :tax_id_by_employee_id, _ -> "1111111111"
        _, _, :get_auth_method, _ -> {:ok, %{"type" => "OTP", "phone_number" => "+380639999999"}}
      end)

      signed_content =
        %{
          "id" => service_request_id,
          "status" => service_request.status,
          "intent" => service_request.intent,
          "category" => ReferenceView.render(service_request.category),
          "code" => ReferenceView.render(service_request.code),
          "context" => ReferenceView.render(service_request.context),
          "authored_on" => service_request.authored_on,
          "requester" => ReferenceView.render(service_request.requester),
          "performer_type" => ReferenceView.render(service_request.performer_type),
          "status_reason" => %{"coding" => [%{"system" => "eHealth/service_request_cancel_reasons", "code" => "1"}]},
          "note" => service_request.note,
          "expiration_date" => service_request.expiration_date,
          "patient_instruction" => service_request.patient_instruction,
          "permitted_episodes" => service_request.permitted_episodes,
          "reason_reference" => service_request.reason_reference,
          "requisition" => service_request.requisition,
          "status_history" => ReferenceView.render(service_request.status_history),
          "used_by" => ReferenceView.render(service_request.used_by),
          "supporting_info" => ReferenceView.render(service_request.supporting_info),
          "patient" =>
            ReferenceView.render(
              Reference.create(%{
                "identifier" => %{
                  "type" => %{"coding" => [%{"system" => "eHealth/resources", "code" => "patient"}], "text" => ""},
                  "value" => patient_id
                }
              })
            ),
          "priority" => nil
        }
        |> Map.merge(ReferenceView.render_occurrence(service_request.occurrence))

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert [
                 %{"collection" => "service_requests", "operation" => "update_one"},
                 %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
               ] = Jason.decode!(args)

        assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

        set_bson = set |> Base.decode64!() |> BSON.decode()

        status = Job.status(:processed)

        response = %{
          "links" => [
            %{
              "entity" => "service_request",
              "href" => "/api/patients/#{patient_id}/service_requests/#{service_request_id}"
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
               Consumer.consume(%ServiceRequestCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end
  end

  defp prepare_signature_expectations do
    user_id = UUID.uuid4()
    drfo = "1111111111"
    expect_signature(drfo)

    user_id
  end
end
