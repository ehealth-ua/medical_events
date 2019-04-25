defmodule Core.Kafka.Consumer.CreateServiceRequestTest do
  @moduledoc false

  use Core.ModelCase

  alias Core.Job
  alias Core.Jobs.ServiceRequestCreateJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  alias Core.ServiceRequest

  import Core.Expectations.DigitalSignatureExpectation
  import Core.Expectations.JobExpectations
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
      diagnostic_report_id = patient.diagnostic_reports |> Map.keys() |> hd()
      service_id = UUID.uuid4()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      expect(WorkerMock, :run, 5, fn
        _, _, :employees_by_user_id_client_id, _ ->
          {:ok, [employee_id]}

        _, _, :tax_id_by_employee_id, _ ->
          "1111111111"

        _, _, :service_by_id, _ ->
          {:ok, %{category: "counselling"}}

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
          "coding" => [%{"code" => "counselling", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "service", "system" => "eHealth/resources"}]},
            "value" => service_id
          }
        },
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester_employee" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "requester_legal_entity" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
            "value" => client_id
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
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
            }
          }
        ],
        "permitted_resources" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
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
      service_id = UUID.uuid4()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      expect(WorkerMock, :run, 4, fn
        _, _, :employees_by_user_id_client_id, _ -> {:ok, [employee_id]}
        _, _, :tax_id_by_employee_id, _ -> "1111111112"
        _, _, :service_by_id, _ -> {:ok, %{category: "counselling"}}
        _, _, :number, _ -> {:ok, UUID.uuid4()}
      end)

      signed_content = %{
        "status" => ServiceRequest.status(:active),
        "intent" => ServiceRequest.intent(:order),
        "category" => %{
          "coding" => [%{"code" => "counselling", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "service", "system" => "eHealth/resources"}]},
            "value" => service_id
          }
        },
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester_employee" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "requester_legal_entity" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
            "value" => client_id
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
        "permitted_resources" => [
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
              "entry" => "$.service_request.requester_employee.identifier.value",
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

    test "fail on permitted resources when category is laboratory procedure" do
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
      diagnostic_report_id = patient.diagnostic_reports |> Map.keys() |> hd()
      service_id = UUID.uuid4()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      expect(WorkerMock, :run, 4, fn
        _, _, :employees_by_user_id_client_id, _ -> {:ok, [employee_id]}
        _, _, :tax_id_by_employee_id, _ -> "1111111111"
        _, _, :service_by_id, _ -> {:ok, %{category: "laboratory_procedure"}}
        _, _, :number, _ -> {:ok, UUID.uuid4()}
      end)

      signed_content = %{
        "status" => ServiceRequest.status(:active),
        "intent" => ServiceRequest.intent(:order),
        "category" => %{
          "coding" => [%{"code" => "laboratory_procedure", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "service", "system" => "eHealth/resources"}]},
            "value" => service_id
          }
        },
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester_employee" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "requester_legal_entity" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
            "value" => client_id
          }
        },
        "permitted_resources" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
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
              "entry" => "$.service_request.permitted_resources",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Permitted resources are not allowed for laboratory category of service request",
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

    test "invalid create service_request params" do
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
      service_id = UUID.uuid4()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      start_datetime =
        DateTime.utc_now()
        |> DateTime.to_unix()
        |> Kernel.-(100_000)
        |> DateTime.from_unix!()
        |> DateTime.to_iso8601()

      end_datetime = DateTime.to_iso8601(DateTime.utc_now())

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

      signed_content = %{
        "status" => ServiceRequest.status(:active),
        "intent" => ServiceRequest.intent(:order),
        "category" => %{
          "coding" => [%{"code" => "counselling", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "service", "system" => "eHealth/resources"}]},
            "value" => service_id
          }
        },
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester_employee" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "requester_legal_entity" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
            "value" => client_id
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
        "permitted_resources" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          }
        ],
        "occurrence_date_time" => DateTime.to_iso8601(DateTime.utc_now()),
        "occurrence_period" => %{
          "start" => start_datetime,
          "end" => end_datetime
        }
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

    test "inavlid permitted resources in service_request params" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      user_id = prepare_signature_expectations()
      job = insert(:job)

      employee_id = UUID.uuid4()

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      patient = insert(:patient, _id: patient_id_hash)
      encounter_id = patient.encounters |> Map.keys() |> hd()
      episode_id = UUID.uuid4()
      diagnostic_report_id = UUID.uuid4()
      service_id = UUID.uuid4()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      expect(WorkerMock, :run, 4, fn
        _, _, :employees_by_user_id_client_id, _ ->
          {:ok, [employee_id]}

        _, _, :tax_id_by_employee_id, _ ->
          "1111111111"

        _, _, :service_by_id, _ ->
          {:ok, %{category: "counselling"}}

        _, _, :number, _ ->
          {:ok, UUID.uuid4()}
      end)

      signed_content = %{
        "status" => ServiceRequest.status(:active),
        "intent" => ServiceRequest.intent(:order),
        "category" => %{
          "coding" => [%{"code" => "counselling", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "service", "system" => "eHealth/resources"}]},
            "value" => service_id
          }
        },
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester_employee" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "requester_legal_entity" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
            "value" => client_id
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
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
            }
          }
        ],
        "permitted_resources" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
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
              "entry" => "$.service_request.permitted_resources.[0].identifier.value",
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
              "entry" => "$.service_request.permitted_resources.[1].identifier.value",
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
              "entry" => "$.service_request.supporting_info.[0].identifier.value",
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
              "entry" => "$.service_request.supporting_info.[1].identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Diagnostic report with such id is not found",
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

    test "invalid code - service reference does not exist" do
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
      diagnostic_report_id = patient.diagnostic_reports |> Map.keys() |> hd()
      service_id = UUID.uuid4()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      expect(WorkerMock, :run, 4, fn
        _, _, :employees_by_user_id_client_id, _ ->
          {:ok, [employee_id]}

        _, _, :tax_id_by_employee_id, _ ->
          "1111111111"

        _, _, :service_by_id, _ ->
          nil

        _, _, :number, _ ->
          {:ok, UUID.uuid4()}
      end)

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.service_request.code.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Service with such ID is not found",
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

      signed_content = %{
        "status" => ServiceRequest.status(:active),
        "intent" => ServiceRequest.intent(:order),
        "category" => %{
          "coding" => [%{"code" => "counselling", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "service", "system" => "eHealth/resources"}]},
            "value" => service_id
          }
        },
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester_employee" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "requester_legal_entity" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
            "value" => client_id
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
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
            }
          }
        ],
        "permitted_resources" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
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

    test "invalid code - service reference is not active" do
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
      diagnostic_report_id = patient.diagnostic_reports |> Map.keys() |> hd()
      service_id = UUID.uuid4()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      expect(WorkerMock, :run, 4, fn
        _, _, :employees_by_user_id_client_id, _ ->
          {:ok, [employee_id]}

        _, _, :tax_id_by_employee_id, _ ->
          "1111111111"

        _, _, :service_by_id, _ ->
          {:ok, %{is_active: false}}

        _, _, :number, _ ->
          {:ok, UUID.uuid4()}
      end)

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.service_request.code.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Service should be active",
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

      signed_content = %{
        "status" => ServiceRequest.status(:active),
        "intent" => ServiceRequest.intent(:order),
        "category" => %{
          "coding" => [%{"code" => "counselling", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "service", "system" => "eHealth/resources"}]},
            "value" => service_id
          }
        },
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester_employee" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "requester_legal_entity" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
            "value" => client_id
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
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
            }
          }
        ],
        "permitted_resources" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
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

    test "invalid code - service reference is not allowed in request" do
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
      diagnostic_report_id = patient.diagnostic_reports |> Map.keys() |> hd()
      service_id = UUID.uuid4()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      expect(WorkerMock, :run, 4, fn
        _, _, :employees_by_user_id_client_id, _ ->
          {:ok, [employee_id]}

        _, _, :tax_id_by_employee_id, _ ->
          "1111111111"

        _, _, :service_by_id, _ ->
          {:ok, %{request_allowed: false}}

        _, _, :number, _ ->
          {:ok, UUID.uuid4()}
      end)

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.service_request.code.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Request is not allowed for the service",
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

      signed_content = %{
        "status" => ServiceRequest.status(:active),
        "intent" => ServiceRequest.intent(:order),
        "category" => %{
          "coding" => [%{"code" => "counselling", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "service", "system" => "eHealth/resources"}]},
            "value" => service_id
          }
        },
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester_employee" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "requester_legal_entity" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
            "value" => client_id
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
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
            }
          }
        ],
        "permitted_resources" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
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

    test "invalid code - service group reference does not exist" do
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
      diagnostic_report_id = patient.diagnostic_reports |> Map.keys() |> hd()
      service_group_id = UUID.uuid4()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      expect(WorkerMock, :run, 4, fn
        _, _, :employees_by_user_id_client_id, _ ->
          {:ok, [employee_id]}

        _, _, :tax_id_by_employee_id, _ ->
          "1111111111"

        _, _, :service_group_by_id, _ ->
          nil

        _, _, :number, _ ->
          {:ok, UUID.uuid4()}
      end)

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.service_request.code.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Service group with such ID is not found",
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

      signed_content = %{
        "status" => ServiceRequest.status(:active),
        "intent" => ServiceRequest.intent(:order),
        "category" => %{
          "coding" => [%{"code" => "counselling", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "service_group", "system" => "eHealth/resources"}]},
            "value" => service_group_id
          }
        },
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester_employee" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "requester_legal_entity" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
            "value" => client_id
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
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
            }
          }
        ],
        "permitted_resources" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
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

    test "invalid code - service group reference is not active" do
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
      diagnostic_report_id = patient.diagnostic_reports |> Map.keys() |> hd()
      service_group_id = UUID.uuid4()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      expect(WorkerMock, :run, 4, fn
        _, _, :employees_by_user_id_client_id, _ ->
          {:ok, [employee_id]}

        _, _, :tax_id_by_employee_id, _ ->
          "1111111111"

        _, _, :service_group_by_id, _ ->
          {:ok, %{is_active: false}}

        _, _, :number, _ ->
          {:ok, UUID.uuid4()}
      end)

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.service_request.code.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Service group should be active",
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

      signed_content = %{
        "status" => ServiceRequest.status(:active),
        "intent" => ServiceRequest.intent(:order),
        "category" => %{
          "coding" => [%{"code" => "counselling", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "service_group", "system" => "eHealth/resources"}]},
            "value" => service_group_id
          }
        },
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester_employee" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "requester_legal_entity" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
            "value" => client_id
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
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
            }
          }
        ],
        "permitted_resources" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
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

    test "invalid code - service group reference is not allowed in request" do
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
      diagnostic_report_id = patient.diagnostic_reports |> Map.keys() |> hd()
      service_group_id = UUID.uuid4()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      expect(WorkerMock, :run, 4, fn
        _, _, :employees_by_user_id_client_id, _ ->
          {:ok, [employee_id]}

        _, _, :tax_id_by_employee_id, _ ->
          "1111111111"

        _, _, :service_group_by_id, _ ->
          {:ok, %{request_allowed: false}}

        _, _, :number, _ ->
          {:ok, UUID.uuid4()}
      end)

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.service_request.code.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Request is not allowed for the service group",
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

      signed_content = %{
        "status" => ServiceRequest.status(:active),
        "intent" => ServiceRequest.intent(:order),
        "category" => %{
          "coding" => [%{"code" => "counselling", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "service_group", "system" => "eHealth/resources"}]},
            "value" => service_group_id
          }
        },
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester_employee" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "requester_legal_entity" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
            "value" => client_id
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
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
            }
          }
        ],
        "permitted_resources" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
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

    test "invalid code category" do
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
      diagnostic_report_id = patient.diagnostic_reports |> Map.keys() |> hd()
      service_id = UUID.uuid4()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      expect(WorkerMock, :run, 4, fn
        _, _, :employees_by_user_id_client_id, _ ->
          {:ok, [employee_id]}

        _, _, :tax_id_by_employee_id, _ ->
          "1111111111"

        _, _, :service_by_id, _ ->
          {:ok, %{category: "111"}}

        _, _, :number, _ ->
          {:ok, UUID.uuid4()}
      end)

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.service_request.code.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Category mismatch",
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

      signed_content = %{
        "status" => ServiceRequest.status(:active),
        "intent" => ServiceRequest.intent(:order),
        "category" => %{
          "coding" => [%{"code" => "counselling", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "service", "system" => "eHealth/resources"}]},
            "value" => service_id
          }
        },
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester_employee" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "requester_legal_entity" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/resources"}]},
            "value" => client_id
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
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
            }
          }
        ],
        "permitted_resources" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
              "value" => diagnostic_report_id
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
  end

  defp prepare_signature_expectations do
    user_id = UUID.uuid4()
    drfo = "1111111111"
    expect_signature(drfo)

    user_id
  end
end
