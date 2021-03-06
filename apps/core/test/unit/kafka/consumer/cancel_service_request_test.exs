defmodule Core.Kafka.Consumer.CancelServiceRequestTest do
  @moduledoc false

  use Core.ModelCase

  alias Core.Encryptor
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.ServiceRequestCancelJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  alias Core.Reference
  alias Core.ReferenceView
  alias Core.ServiceRequest
  import Core.Expectations.DigitalSignatureExpectation
  import Core.Expectations.JobExpectations
  import Core.Expectations.OTPVerificationExpectations
  import Mox

  @status_pending Job.status(:pending)

  setup :verify_on_exit!

  describe "consume cancel service_request event" do
    test "empty map" do
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
            "entry" => "$.requester_employee",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property requester_employee was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.requester_legal_entity",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property requester_legal_entity was not present",
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
            "entry" => "$.used_by_employee",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property used_by_employee was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.used_by_legal_entity",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property used_by_legal_entity was not present",
                "params" => [],
                "rule" => "required"
              }
            ]
          },
          %{
            "entry" => "$.subject",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "required property subject was not present",
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
          "requester_employee" => ReferenceView.render(service_request.requester_employee),
          "requester_legal_entity" => ReferenceView.render(service_request.requester_legal_entity),
          "status_reason" => %{"coding" => [%{"system" => "eHealth/service_request_cancel_reasons", "code" => "1"}]},
          "note" => "invalid",
          "expiration_date" => service_request.expiration_date,
          "patient_instruction" => service_request.patient_instruction,
          "permitted_resources" => service_request.permitted_resources,
          "reason_reference" => service_request.reason_reference,
          "requisition" => Encryptor.decrypt(service_request.requisition),
          "status_history" => ReferenceView.render(service_request.status_history),
          "used_by_employee" => ReferenceView.render(service_request.used_by_employee),
          "used_by_legal_entity" => ReferenceView.render(service_request.used_by_legal_entity),
          "supporting_info" => ReferenceView.render(service_request.supporting_info),
          "subject" =>
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

      error = %{
        "invalid" => [
          %{
            "entry" => "$.signed_data",
            "entry_type" => "json_data_property",
            "rules" => [
              %{
                "description" => "Signed content doesn't match with previously created service request",
                "params" => [],
                "rule" => "invalid"
              }
            ]
          }
        ],
        "message" =>
          "Validation failed. You can find validators description at our API Manifest: http://docs.apimanifest.apiary.io/#introduction/interacting-with-api/errors.",
        "type" => "validation_failed"
      }

      expect_job_update(job._id, Job.status(:failed), error, 422)

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
      employee_id = to_string(service_request.requester_employee.identifier.value)

      expect(WorkerMock, :run, 3, fn
        _, _, :employees_by_user_id_client_id, _ -> {:ok, [employee_id]}
        _, _, :tax_id_by_employee_id, _ -> "1111111111"
        _, _, :get_auth_method, _ -> {:ok, %{"type" => "OTP", "phone_number" => "+380639999999"}}
      end)

      expect_otp_verification_send_sms()

      status = ServiceRequest.status(:entered_in_error)

      expect(KafkaMock, :publish_to_event_manager, fn event ->
        assert %{
                 event_type: "StatusChangeEvent",
                 entity_type: "ServiceRequest",
                 entity_id: ^service_request_id,
                 changed_by: _actor_id,
                 properties: %{"status" => %{"new_value" => ^status}}
               } = event

        :ok
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
          "requester_employee" => ReferenceView.render(service_request.requester_employee),
          "requester_legal_entity" => ReferenceView.render(service_request.requester_legal_entity),
          "status_reason" => %{"coding" => [%{"system" => "eHealth/service_request_cancel_reasons", "code" => "1"}]},
          "note" => service_request.note,
          "expiration_date" => service_request.expiration_date,
          "patient_instruction" => service_request.patient_instruction,
          "permitted_resources" => service_request.permitted_resources,
          "reason_reference" => service_request.reason_reference,
          "requisition" => Encryptor.decrypt(service_request.requisition),
          "status_history" => ReferenceView.render(service_request.status_history),
          "used_by_employee" => ReferenceView.render(service_request.used_by_employee),
          "used_by_legal_entity" => ReferenceView.render(service_request.used_by_legal_entity),
          "supporting_info" => ReferenceView.render(service_request.supporting_info),
          "subject" =>
            ReferenceView.render(
              Reference.create(%{
                "identifier" => %{
                  "type" => %{"coding" => [%{"system" => "eHealth/resources", "code" => "patient"}], "text" => ""},
                  "value" => patient_id
                }
              })
            ),
          "priority" => nil,
          "completed_with" => ReferenceView.render(service_request.completed_with)
        }
        |> Map.merge(ReferenceView.render_occurrence(service_request.occurrence))

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [
                   %{"collection" => "service_requests", "operation" => "update_one"},
                   %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
                 ]
               } = Jason.decode!(args)

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
                 signed_data: Base.encode64(Jason.encode!(signed_content)),
                 service_request_id: service_request_id
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end

    test "invalid cancel service_request params" do
      client_id = UUID.uuid4()
      user_id = prepare_signature_expectations()
      job = insert(:job)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      service_request = insert(:service_request, subject: patient_id_hash)
      %BSON.Binary{binary: id} = service_request._id
      service_request_id = UUID.binary_to_string!(id)
      insert(:patient, _id: patient_id_hash)

      start_datetime =
        DateTime.utc_now()
        |> DateTime.to_unix()
        |> Kernel.-(100_000)
        |> DateTime.from_unix!()
        |> DateTime.to_iso8601()

      end_datetime = DateTime.to_iso8601(DateTime.utc_now())

      signed_content =
        %{
          "id" => service_request_id,
          "status" => service_request.status,
          "intent" => service_request.intent,
          "category" => ReferenceView.render(service_request.category),
          "code" => ReferenceView.render(service_request.code),
          "context" => ReferenceView.render(service_request.context),
          "authored_on" => service_request.authored_on,
          "requester_employee" => ReferenceView.render(service_request.requester_employee),
          "requester_legal_entity" => ReferenceView.render(service_request.requester_legal_entity),
          "status_reason" => %{"coding" => [%{"system" => "eHealth/service_request_cancel_reasons", "code" => "1"}]},
          "note" => service_request.note,
          "expiration_date" => service_request.expiration_date,
          "patient_instruction" => service_request.patient_instruction,
          "permitted_resources" => service_request.permitted_resources,
          "reason_reference" => service_request.reason_reference,
          "requisition" => Encryptor.decrypt(service_request.requisition),
          "status_history" => ReferenceView.render(service_request.status_history),
          "used_by_employee" => ReferenceView.render(service_request.used_by_employee),
          "used_by_legal_entity" => ReferenceView.render(service_request.used_by_legal_entity),
          "supporting_info" => ReferenceView.render(service_request.supporting_info),
          "subject" =>
            ReferenceView.render(
              Reference.create(%{
                "identifier" => %{
                  "type" => %{"coding" => [%{"system" => "eHealth/resources", "code" => "patient"}], "text" => ""},
                  "value" => patient_id
                }
              })
            ),
          "priority" => nil,
          "occurrence_date_time" => DateTime.to_iso8601(DateTime.utc_now()),
          "occurrence_period" => %{
            "start" => start_datetime,
            "end" => end_datetime
          }
        }
        |> Map.merge(ReferenceView.render_occurrence(service_request.occurrence))

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.occurrence_date_time",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => ["$.occurrence_date_time", "$.occurrence_period"],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.occurrence_period",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => ["$.occurrence_date_time", "$.occurrence_period"],
                  "rule" => "oneOf"
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
