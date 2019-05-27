defmodule Core.Kafka.Consumer.CreateDiagnoisticReportPackageTest do
  @moduledoc false

  use Core.ModelCase

  import Core.Expectations.DigitalSignatureExpectation
  import Core.Expectations.IlExpectations
  import Mox

  alias Core.Job
  alias Core.Jobs.DiagnosticReportPackageCreateJob
  alias Core.Kafka.Consumer
  alias Core.Mongo
  alias Core.Observation
  alias Core.Patients

  @status_valid Observation.status(:valid)
  @drfo "1111111111"

  setup :verify_on_exit!

  describe "consume create package event" do
    test "empty content" do
      job = insert(:job)
      user_id = UUID.uuid4()
      expect_signature(@drfo)

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
               Consumer.consume(%DiagnosticReportPackageCreateJob{
                 _id: to_string(job._id),
                 signed_data: Base.encode64(""),
                 user_id: user_id,
                 client_id: UUID.uuid4()
               })
    end

    test "empty map" do
      job = insert(:job)
      user_id = UUID.uuid4()
      expect_signature(@drfo)

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.diagnostic_report",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "required property diagnostic_report was not present",
                  "params" => [],
                  "rule" => "required"
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
               Consumer.consume(%DiagnosticReportPackageCreateJob{
                 _id: to_string(job._id),
                 signed_data: Base.encode64(Jason.encode!(%{})),
                 user_id: user_id,
                 client_id: UUID.uuid4()
               })
    end

    test "success create package" do
      expect(MediaStorageMock, :save, fn _, _, _, _ -> :ok end)
      client_id = UUID.uuid4()
      user_id = UUID.uuid4()
      expect_signature(@drfo)
      expect_employee_users(@drfo, user_id)
      expect_doctor(client_id)

      expect(WorkerMock, :run, fn
        _, _, :service_by_id, _ -> {:ok, %{category: "category"}}
      end)

      expect_doctor(client_id)

      expect(IlMock, :get_legal_entity, fn id, _ ->
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

      episode =
        build(
          :episode,
          managing_organization:
            build(
              :reference,
              identifier:
                build(
                  :identifier,
                  type: build(:codeable_concept, coding: [build(:coding)]),
                  value: Mongo.string_to_uuid(client_id)
                )
            )
        )

      db_immunization_id = UUID.uuid4()
      immunization = build(:immunization, id: Mongo.string_to_uuid(db_immunization_id), reactions: [build(:reaction)])

      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))

      insert(
        :patient,
        _id: patient_id_hash,
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter},
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        immunizations: %{db_immunization_id => immunization}
      )

      insert(:observation, patient_id: patient_id_hash)
      immunization_id = UUID.uuid4()
      job = insert(:job)
      observation_id = UUID.uuid4()
      observation_id2 = UUID.uuid4()
      employee_id = UUID.uuid4()
      diagnostic_report_id = UUID.uuid4()
      service_id = UUID.uuid4()

      service_request =
        insert(:service_request,
          used_by_employee: build(:reference),
          used_by_legal_entity:
            build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(client_id))),
          code:
            build(:reference,
              identifier:
                build(:identifier,
                  type: codeable_concept_coding(code: "service"),
                  value: Mongo.string_to_uuid(service_id)
                )
            )
        )

      start_datetime =
        DateTime.utc_now()
        |> DateTime.to_unix()
        |> Kernel.-(100_000)
        |> DateTime.from_unix!()
        |> DateTime.to_iso8601()

      end_datetime = DateTime.to_iso8601(DateTime.utc_now())

      signed_content = %{
        "observations" => [
          %{
            "id" => observation_id,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "diagnostic_report" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                "value" => diagnostic_report_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{
              "coding" => [
                %{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"},
                %{"code" => "B70", "system" => "eHealth/LOINC/observation_codes"}
              ]
            },
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "interpretation" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/observation_interpretations"}]
            },
            "body_site" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/body_sites"}]
            },
            "method" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/observation_methods"}]
            },
            "value_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "reference_ranges" => [
              %{
                "type" => %{"coding" => [%{"code" => "category", "system" => "eHealth/reference_range_types"}]},
                "applies_to" => [
                  %{
                    "coding" => [%{"code" => "category", "system" => "eHealth/reference_range_applications"}]
                  }
                ]
              }
            ],
            "components" => [
              %{
                "code" => %{
                  "coding" => [%{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"}]
                },
                "value_period" => %{
                  "start" => start_datetime,
                  "end" => end_datetime
                },
                "interpretation" => %{
                  "coding" => [%{"code" => "1", "system" => "eHealth/observation_interpretations"}]
                },
                "reference_ranges" => [
                  %{
                    "applies_to" => [
                      %{
                        "coding" => [%{"code" => "category", "system" => "eHealth/reference_range_applications"}]
                      }
                    ]
                  }
                ]
              }
            ],
            "reaction_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "immunization"
                    }
                  ]
                },
                "value" => immunization_id
              }
            }
          },
          %{
            "id" => observation_id2,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "diagnostic_report" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                "value" => diagnostic_report_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{"coding" => [%{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"}]},
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "reaction_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "immunization"
                    }
                  ]
                },
                "value" => db_immunization_id
              }
            },
            "value_time" => "12:00:00"
          }
        ],
        "diagnostic_report" => %{
          "id" => diagnostic_report_id,
          "based_on" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service_request"
                  }
                ]
              },
              "value" => to_string(service_request._id)
            }
          },
          "status" => "final",
          "category" => [
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "LAB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            }
          ],
          "code" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service"
                  }
                ]
              },
              "value" => service_id
            }
          },
          "effective_period" => %{
            "start" => "2018-08-02T10:45:16.000Z",
            "end" => "2018-08-02T11:00:00.000Z"
          },
          "issued" => "2018-10-08T09:46:37.694Z",
          "conclusion" => "At risk of osteoporotic fracture",
          "conclusion_code" => %{
            "coding" => [
              %{
                "system" => "eHealth/SNOMED/clinical_findings",
                "code" => "109006"
              }
            ]
          },
          "recorded_by" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "employee"
                  }
                ]
              },
              "value" => employee_id
            }
          },
          "primary_source" => true,
          "managing_organization" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "legal_entity"
                  }
                ]
              },
              "value" => client_id
            }
          },
          "performer" => %{
            "reference" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "employee"
                    }
                  ]
                },
                "value" => employee_id
              }
            }
          },
          "results_interpreter" => %{
            "reference" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "employee"
                    }
                  ]
                },
                "value" => employee_id
              }
            }
          }
        }
      }

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [
                   %{"collection" => "patients", "operation" => "update_one", "set" => patient_data},
                   %{"collection" => "observations", "operation" => "insert"},
                   %{"collection" => "observations", "operation" => "insert"},
                   %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
                 ]
               } = Jason.decode!(args)

        assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

        set_bson = set |> Base.decode64!() |> BSON.decode()
        status = Job.status(:processed)

        response = %{
          "links" => [
            %{
              "entity" => "diagnostic_report",
              "href" => "/api/patients/#{patient_id}/diagnostic_reports/#{diagnostic_report_id}"
            },
            %{
              "entity" => "observation",
              "href" => "/api/patients/#{patient_id}/observations/#{observation_id}"
            },
            %{
              "entity" => "observation",
              "href" => "/api/patients/#{patient_id}/observations/#{observation_id2}"
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
               Consumer.consume(%DiagnosticReportPackageCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end

    test "invalid create package request params" do
      client_id = UUID.uuid4()
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      episode =
        build(
          :episode,
          managing_organization:
            build(
              :reference,
              identifier:
                build(
                  :identifier,
                  type: build(:codeable_concept, coding: [build(:coding)]),
                  value: Mongo.string_to_uuid(client_id)
                )
            )
        )

      db_immunization_id = UUID.uuid4()
      immunization = build(:immunization, id: Mongo.string_to_uuid(db_immunization_id), reactions: [build(:reaction)])

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        immunizations: %{db_immunization_id => immunization}
      )

      insert(:observation, patient_id: patient_id_hash)
      immunization_id = UUID.uuid4()
      job = insert(:job)
      user_id = UUID.uuid4()
      expect_signature(@drfo)
      observation_id = UUID.uuid4()
      observation_id2 = UUID.uuid4()
      employee_id = UUID.uuid4()
      diagnostic_report_id = UUID.uuid4()
      service_id = UUID.uuid4()

      service_request =
        insert(:service_request,
          used_by_employee: build(:reference),
          used_by_legal_entity:
            build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(client_id)))
        )

      start_datetime =
        DateTime.utc_now()
        |> DateTime.to_unix()
        |> Kernel.-(100_000)
        |> DateTime.from_unix!()
        |> DateTime.to_iso8601()

      end_datetime = DateTime.to_iso8601(DateTime.utc_now())

      signed_content = %{
        "observations" => [
          %{
            "id" => observation_id,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "diagnostic_report" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                "value" => diagnostic_report_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{
              "coding" => [
                %{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"},
                %{"code" => "B70", "system" => "eHealth/LOINC/observation_codes"}
              ]
            },
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "interpretation" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/observation_interpretations"}]
            },
            "body_site" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/body_sites"}]
            },
            "method" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/observation_methods"}]
            },
            "reference_ranges" => [
              %{
                "type" => %{"coding" => [%{"code" => "category", "system" => "eHealth/reference_range_types"}]},
                "applies_to" => [
                  %{
                    "coding" => [%{"code" => "category", "system" => "eHealth/reference_range_applications"}]
                  }
                ]
              }
            ],
            "components" => [
              %{
                "code" => %{
                  "coding" => [%{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"}]
                },
                "value_period" => %{
                  "start" => start_datetime,
                  "end" => end_datetime
                },
                "value_string" => "test",
                "value_boolean" => true,
                "interpretation" => %{
                  "coding" => [%{"code" => "1", "system" => "eHealth/observation_interpretations"}]
                },
                "reference_ranges" => [
                  %{
                    "applies_to" => [
                      %{
                        "coding" => [%{"code" => "category", "system" => "eHealth/reference_range_applications"}]
                      }
                    ]
                  }
                ]
              }
            ],
            "reaction_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "immunization"
                    }
                  ]
                },
                "value" => immunization_id
              }
            }
          },
          %{
            "id" => observation_id2,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "diagnostic_report" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                "value" => diagnostic_report_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{"coding" => [%{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"}]},
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "effective_date_time" => DateTime.to_iso8601(DateTime.utc_now()),
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "reaction_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "immunization"
                    }
                  ]
                },
                "value" => db_immunization_id
              }
            },
            "value_time" => "12:00:00"
          }
        ],
        "diagnostic_report" => %{
          "id" => diagnostic_report_id,
          "based_on" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service_request"
                  }
                ]
              },
              "value" => to_string(service_request._id)
            }
          },
          "status" => "final",
          "category" => [
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "LAB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            }
          ],
          "code" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service"
                  }
                ]
              },
              "value" => service_id
            }
          },
          "effective_period" => %{
            "start" => "2018-08-02T10:45:16.000Z",
            "end" => "2018-08-02T11:00:00.000Z"
          },
          "issued" => "2018-10-08T09:46:37.694Z",
          "conclusion" => "At risk of osteoporotic fracture",
          "conclusion_code" => %{
            "coding" => [
              %{
                "system" => "eHealth/SNOMED/clinical_findings",
                "code" => "109006"
              }
            ]
          },
          "recorded_by" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "employee"
                  }
                ]
              },
              "value" => employee_id
            }
          },
          "primary_source" => true,
          "managing_organization" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "legal_entity"
                  }
                ]
              },
              "value" => client_id
            }
          },
          "performer" => %{
            "reference" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "employee"
                    }
                  ]
                },
                "value" => employee_id
              }
            },
            "text" => ""
          },
          "results_interpreter" => %{
            "reference" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "employee"
                    }
                  ]
                },
                "value" => employee_id
              }
            },
            "text" => ""
          }
        }
      }

      # expected error results:
      #   observations:
      #     "report_origin", "performer": none of OneOf parameters are sent
      #     "effective_date_time", "effective_period": all OneOf parameters are sent
      #     "value_quantity", "value_codeable_concept", "value_sampled_data", "value_string", "value_boolean",
      #         "value_range", "value_ratio", "value_time", "value_date_time", "value_period": none of OneOf parameters are sent
      #     components:
      #       "value_quantity", "value_codeable_concept", "value_sampled_data", "value_string", "value_boolean",
      #           "value_range", "value_ratio", "value_time", "value_date_time", "value_period": more than one OneOf parameters are sent
      #   diagnostic_report:
      #     performer:
      #       "reference", "text": all OneOf parameters are sent
      #     results_interpreter:
      #       "reference", "text": all OneOf parameters are sent

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.diagnostic_report.performer.reference",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => ["$.diagnostic_report.performer.reference", "$.diagnostic_report.performer.text"],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.diagnostic_report.performer.text",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => ["$.diagnostic_report.performer.reference", "$.diagnostic_report.performer.text"],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.diagnostic_report.results_interpreter.reference",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => [
                    "$.diagnostic_report.results_interpreter.reference",
                    "$.diagnostic_report.results_interpreter.text"
                  ],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.diagnostic_report.results_interpreter.text",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => [
                    "$.diagnostic_report.results_interpreter.reference",
                    "$.diagnostic_report.results_interpreter.text"
                  ],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.observations[0]",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "At least one of the parameters must be present",
                  "params" => [
                    "$.observations[0].value_quantity",
                    "$.observations[0].value_codeable_concept",
                    "$.observations[0].value_sampled_data",
                    "$.observations[0].value_string",
                    "$.observations[0].value_boolean",
                    "$.observations[0].value_range",
                    "$.observations[0].value_ratio",
                    "$.observations[0].value_time",
                    "$.observations[0].value_date_time",
                    "$.observations[0].value_period"
                  ],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.observations[1].effective_date_time",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => ["$.observations[1].effective_date_time", "$.observations[1].effective_period"],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.observations[1].effective_period",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => ["$.observations[1].effective_date_time", "$.observations[1].effective_period"],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.observations[0].components[0].value_boolean",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => [
                    "$.observations[0].components[0].value_quantity",
                    "$.observations[0].components[0].value_codeable_concept",
                    "$.observations[0].components[0].value_sampled_data",
                    "$.observations[0].components[0].value_string",
                    "$.observations[0].components[0].value_boolean",
                    "$.observations[0].components[0].value_range",
                    "$.observations[0].components[0].value_ratio",
                    "$.observations[0].components[0].value_time",
                    "$.observations[0].components[0].value_date_time",
                    "$.observations[0].components[0].value_period"
                  ],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.observations[0].components[0].value_period",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => [
                    "$.observations[0].components[0].value_quantity",
                    "$.observations[0].components[0].value_codeable_concept",
                    "$.observations[0].components[0].value_sampled_data",
                    "$.observations[0].components[0].value_string",
                    "$.observations[0].components[0].value_boolean",
                    "$.observations[0].components[0].value_range",
                    "$.observations[0].components[0].value_ratio",
                    "$.observations[0].components[0].value_time",
                    "$.observations[0].components[0].value_date_time",
                    "$.observations[0].components[0].value_period"
                  ],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.observations[0].components[0].value_string",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => [
                    "$.observations[0].components[0].value_quantity",
                    "$.observations[0].components[0].value_codeable_concept",
                    "$.observations[0].components[0].value_sampled_data",
                    "$.observations[0].components[0].value_string",
                    "$.observations[0].components[0].value_boolean",
                    "$.observations[0].components[0].value_range",
                    "$.observations[0].components[0].value_ratio",
                    "$.observations[0].components[0].value_time",
                    "$.observations[0].components[0].value_date_time",
                    "$.observations[0].components[0].value_period"
                  ],
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
               Consumer.consume(%DiagnosticReportPackageCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end

    test "conclusion must be filled when service category is diagnostic_procedure" do
      client_id = UUID.uuid4()
      user_id = UUID.uuid4()
      expect_signature(@drfo)
      expect_employee_users(@drfo, user_id)
      expect_doctor(client_id)

      expect(WorkerMock, :run, fn
        _, _, :service_by_id, _ -> {:ok, %{category: "diagnostic_procedure"}}
      end)

      expect_doctor(client_id)

      expect(IlMock, :get_legal_entity, fn id, _ ->
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

      episode =
        build(
          :episode,
          managing_organization:
            build(
              :reference,
              identifier:
                build(
                  :identifier,
                  type: build(:codeable_concept, coding: [build(:coding)]),
                  value: Mongo.string_to_uuid(client_id)
                )
            )
        )

      db_immunization_id = UUID.uuid4()
      immunization = build(:immunization, id: Mongo.string_to_uuid(db_immunization_id), reactions: [build(:reaction)])

      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))

      insert(
        :patient,
        _id: patient_id_hash,
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter},
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        immunizations: %{db_immunization_id => immunization}
      )

      insert(:observation, patient_id: patient_id_hash)
      immunization_id = UUID.uuid4()
      job = insert(:job)
      observation_id = UUID.uuid4()
      observation_id2 = UUID.uuid4()
      employee_id = UUID.uuid4()
      diagnostic_report_id = UUID.uuid4()
      service_id = UUID.uuid4()

      service_request =
        insert(:service_request,
          used_by_employee: build(:reference),
          used_by_legal_entity:
            build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(client_id))),
          code:
            build(:reference,
              identifier:
                build(:identifier,
                  type: codeable_concept_coding(code: "service"),
                  value: Mongo.string_to_uuid(service_id)
                )
            )
        )

      start_datetime =
        DateTime.utc_now()
        |> DateTime.to_unix()
        |> Kernel.-(100_000)
        |> DateTime.from_unix!()
        |> DateTime.to_iso8601()

      end_datetime = DateTime.to_iso8601(DateTime.utc_now())

      signed_content = %{
        "observations" => [
          %{
            "id" => observation_id,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "diagnostic_report" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                "value" => diagnostic_report_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{
              "coding" => [
                %{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"},
                %{"code" => "B70", "system" => "eHealth/LOINC/observation_codes"}
              ]
            },
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "interpretation" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/observation_interpretations"}]
            },
            "body_site" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/body_sites"}]
            },
            "method" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/observation_methods"}]
            },
            "value_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "reference_ranges" => [
              %{
                "type" => %{"coding" => [%{"code" => "category", "system" => "eHealth/reference_range_types"}]},
                "applies_to" => [
                  %{
                    "coding" => [%{"code" => "category", "system" => "eHealth/reference_range_applications"}]
                  }
                ]
              }
            ],
            "components" => [
              %{
                "code" => %{
                  "coding" => [%{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"}]
                },
                "value_period" => %{
                  "start" => start_datetime,
                  "end" => end_datetime
                },
                "interpretation" => %{
                  "coding" => [%{"code" => "1", "system" => "eHealth/observation_interpretations"}]
                },
                "reference_ranges" => [
                  %{
                    "applies_to" => [
                      %{
                        "coding" => [%{"code" => "category", "system" => "eHealth/reference_range_applications"}]
                      }
                    ]
                  }
                ]
              }
            ],
            "reaction_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "immunization"
                    }
                  ]
                },
                "value" => immunization_id
              }
            }
          },
          %{
            "id" => observation_id2,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "diagnostic_report" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                "value" => diagnostic_report_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{"coding" => [%{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"}]},
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "reaction_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "immunization"
                    }
                  ]
                },
                "value" => db_immunization_id
              }
            },
            "value_time" => "12:00:00"
          }
        ],
        "diagnostic_report" => %{
          "id" => diagnostic_report_id,
          "based_on" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service_request"
                  }
                ]
              },
              "value" => to_string(service_request._id)
            }
          },
          "status" => "final",
          "category" => [
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "LAB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            }
          ],
          "code" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service"
                  }
                ]
              },
              "value" => service_id
            }
          },
          "effective_period" => %{
            "start" => "2018-08-02T10:45:16.000Z",
            "end" => "2018-08-02T11:00:00.000Z"
          },
          "issued" => "2018-10-08T09:46:37.694Z",
          "conclusion_code" => %{
            "coding" => [
              %{
                "system" => "eHealth/SNOMED/clinical_findings",
                "code" => "109006"
              }
            ]
          },
          "recorded_by" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "employee"
                  }
                ]
              },
              "value" => employee_id
            }
          },
          "primary_source" => true,
          "managing_organization" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "legal_entity"
                  }
                ]
              },
              "value" => client_id
            }
          },
          "performer" => %{
            "reference" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "employee"
                    }
                  ]
                },
                "value" => employee_id
              }
            }
          },
          "results_interpreter" => %{
            "reference" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "employee"
                    }
                  ]
                },
                "value" => employee_id
              }
            }
          }
        }
      }

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.diagnostic_report.conclusion",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Must be filled when service category is diagnostic_procedure or imaging",
                  "params" => [],
                  "rule" => nil
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
               Consumer.consume(%DiagnosticReportPackageCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end

    test "results_interpreter with type reference must be filled when service category is diagnostic_procedure" do
      client_id = UUID.uuid4()
      user_id = UUID.uuid4()
      expect_signature(@drfo)
      expect_employee_users(@drfo, user_id)
      expect_doctor(client_id)

      expect(WorkerMock, :run, fn
        _, _, :service_by_id, _ -> {:ok, %{category: "diagnostic_procedure"}}
      end)

      expect_doctor(client_id)

      expect(IlMock, :get_legal_entity, fn id, _ ->
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

      episode =
        build(
          :episode,
          managing_organization:
            build(
              :reference,
              identifier:
                build(
                  :identifier,
                  type: build(:codeable_concept, coding: [build(:coding)]),
                  value: Mongo.string_to_uuid(client_id)
                )
            )
        )

      db_immunization_id = UUID.uuid4()
      immunization = build(:immunization, id: Mongo.string_to_uuid(db_immunization_id), reactions: [build(:reaction)])

      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))

      insert(
        :patient,
        _id: patient_id_hash,
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter},
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        immunizations: %{db_immunization_id => immunization}
      )

      insert(:observation, patient_id: patient_id_hash)
      immunization_id = UUID.uuid4()
      job = insert(:job)
      observation_id = UUID.uuid4()
      observation_id2 = UUID.uuid4()
      employee_id = UUID.uuid4()
      diagnostic_report_id = UUID.uuid4()
      service_id = UUID.uuid4()

      service_request =
        insert(:service_request,
          used_by_employee: build(:reference),
          used_by_legal_entity:
            build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(client_id))),
          code:
            build(:reference,
              identifier:
                build(:identifier,
                  type: codeable_concept_coding(code: "service"),
                  value: Mongo.string_to_uuid(service_id)
                )
            )
        )

      start_datetime =
        DateTime.utc_now()
        |> DateTime.to_unix()
        |> Kernel.-(100_000)
        |> DateTime.from_unix!()
        |> DateTime.to_iso8601()

      end_datetime = DateTime.to_iso8601(DateTime.utc_now())

      signed_content = %{
        "observations" => [
          %{
            "id" => observation_id,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "diagnostic_report" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                "value" => diagnostic_report_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{
              "coding" => [
                %{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"},
                %{"code" => "B70", "system" => "eHealth/LOINC/observation_codes"}
              ]
            },
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "interpretation" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/observation_interpretations"}]
            },
            "body_site" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/body_sites"}]
            },
            "method" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/observation_methods"}]
            },
            "value_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "reference_ranges" => [
              %{
                "type" => %{"coding" => [%{"code" => "category", "system" => "eHealth/reference_range_types"}]},
                "applies_to" => [
                  %{
                    "coding" => [%{"code" => "category", "system" => "eHealth/reference_range_applications"}]
                  }
                ]
              }
            ],
            "components" => [
              %{
                "code" => %{
                  "coding" => [%{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"}]
                },
                "value_period" => %{
                  "start" => start_datetime,
                  "end" => end_datetime
                },
                "interpretation" => %{
                  "coding" => [%{"code" => "1", "system" => "eHealth/observation_interpretations"}]
                },
                "reference_ranges" => [
                  %{
                    "applies_to" => [
                      %{
                        "coding" => [%{"code" => "category", "system" => "eHealth/reference_range_applications"}]
                      }
                    ]
                  }
                ]
              }
            ],
            "reaction_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "immunization"
                    }
                  ]
                },
                "value" => immunization_id
              }
            }
          },
          %{
            "id" => observation_id2,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "diagnostic_report" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                "value" => diagnostic_report_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{"coding" => [%{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"}]},
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "reaction_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "immunization"
                    }
                  ]
                },
                "value" => db_immunization_id
              }
            },
            "value_time" => "12:00:00"
          }
        ],
        "diagnostic_report" => %{
          "id" => diagnostic_report_id,
          "based_on" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service_request"
                  }
                ]
              },
              "value" => to_string(service_request._id)
            }
          },
          "status" => "final",
          "category" => [
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "LAB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            }
          ],
          "code" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service"
                  }
                ]
              },
              "value" => service_id
            }
          },
          "effective_period" => %{
            "start" => "2018-08-02T10:45:16.000Z",
            "end" => "2018-08-02T11:00:00.000Z"
          },
          "issued" => "2018-10-08T09:46:37.694Z",
          "conclusion" => "At risk of osteoporotic fracture",
          "conclusion_code" => %{
            "coding" => [
              %{
                "system" => "eHealth/SNOMED/clinical_findings",
                "code" => "109006"
              }
            ]
          },
          "recorded_by" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "employee"
                  }
                ]
              },
              "value" => employee_id
            }
          },
          "primary_source" => true,
          "managing_organization" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "legal_entity"
                  }
                ]
              },
              "value" => client_id
            }
          },
          "performer" => %{
            "reference" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "employee"
                    }
                  ]
                },
                "value" => employee_id
              }
            }
          }
        }
      }

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.diagnostic_report.results_interpreter",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" =>
                    "results_interpreter with type reference must be filled when service category is diagnostic_procedure or imaging",
                  "params" => [],
                  "rule" => "required"
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
               Consumer.consume(%DiagnosticReportPackageCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end

    test "observations must be filled when service category is laboratory" do
      client_id = UUID.uuid4()
      user_id = UUID.uuid4()
      expect_signature(@drfo)
      expect_employee_users(@drfo, user_id)

      expect(WorkerMock, :run, fn
        _, _, :service_by_id, _ -> {:ok, %{category: "laboratory"}}
      end)

      expect_doctor(client_id, 2)

      expect(IlMock, :get_legal_entity, fn id, _ ->
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

      episode =
        build(
          :episode,
          managing_organization:
            build(
              :reference,
              identifier:
                build(
                  :identifier,
                  type: build(:codeable_concept, coding: [build(:coding)]),
                  value: Mongo.string_to_uuid(client_id)
                )
            )
        )

      db_immunization_id = UUID.uuid4()
      immunization = build(:immunization, id: Mongo.string_to_uuid(db_immunization_id), reactions: [build(:reaction)])

      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))

      insert(
        :patient,
        _id: patient_id_hash,
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter},
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        immunizations: %{db_immunization_id => immunization}
      )

      job = insert(:job)
      employee_id = UUID.uuid4()
      diagnostic_report_id = UUID.uuid4()
      service_id = UUID.uuid4()

      service_request =
        insert(:service_request,
          used_by_employee: build(:reference),
          used_by_legal_entity:
            build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(client_id))),
          code:
            build(:reference,
              identifier:
                build(:identifier,
                  type: codeable_concept_coding(code: "service"),
                  value: Mongo.string_to_uuid(service_id)
                )
            )
        )

      signed_content = %{
        "diagnostic_report" => %{
          "id" => diagnostic_report_id,
          "based_on" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service_request"
                  }
                ]
              },
              "value" => to_string(service_request._id)
            }
          },
          "status" => "final",
          "category" => [
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "LAB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            }
          ],
          "code" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service"
                  }
                ]
              },
              "value" => service_id
            }
          },
          "effective_period" => %{
            "start" => "2018-08-02T10:45:16.000Z",
            "end" => "2018-08-02T11:00:00.000Z"
          },
          "issued" => "2018-10-08T09:46:37.694Z",
          "conclusion" => "At risk of osteoporotic fracture",
          "conclusion_code" => %{
            "coding" => [
              %{
                "system" => "eHealth/SNOMED/clinical_findings",
                "code" => "109006"
              }
            ]
          },
          "recorded_by" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "employee"
                  }
                ]
              },
              "value" => employee_id
            }
          },
          "primary_source" => true,
          "managing_organization" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "legal_entity"
                  }
                ]
              },
              "value" => client_id
            }
          },
          "performer" => %{
            "reference" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "employee"
                    }
                  ]
                },
                "value" => employee_id
              }
            }
          },
          "results_interpreter" => %{
            "reference" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "employee"
                    }
                  ]
                },
                "value" => employee_id
              }
            }
          }
        }
      }

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.diagnostic_report.code.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Observations are mandatory when service category = laboratory",
                  "params" => [],
                  "rule" => nil
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
               Consumer.consume(%DiagnosticReportPackageCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end

    test "service request category should be equal to service category" do
      client_id = UUID.uuid4()
      user_id = UUID.uuid4()
      expect_signature(@drfo)
      expect_employee_users(@drfo, user_id)
      expect_doctor(client_id)

      expect(WorkerMock, :run, fn
        _, _, :service_by_id, _ -> {:ok, %{category: "category"}}
      end)

      expect_doctor(client_id)

      expect(IlMock, :get_legal_entity, fn id, _ ->
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

      episode =
        build(
          :episode,
          managing_organization:
            build(
              :reference,
              identifier:
                build(
                  :identifier,
                  type: build(:codeable_concept, coding: [build(:coding)]),
                  value: Mongo.string_to_uuid(client_id)
                )
            )
        )

      db_immunization_id = UUID.uuid4()
      immunization = build(:immunization, id: Mongo.string_to_uuid(db_immunization_id), reactions: [build(:reaction)])

      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))

      insert(
        :patient,
        _id: patient_id_hash,
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter},
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        immunizations: %{db_immunization_id => immunization}
      )

      insert(:observation, patient_id: patient_id_hash)
      immunization_id = UUID.uuid4()
      job = insert(:job)
      observation_id = UUID.uuid4()
      observation_id2 = UUID.uuid4()
      employee_id = UUID.uuid4()
      diagnostic_report_id = UUID.uuid4()
      service_id = UUID.uuid4()
      service_group_id = UUID.uuid4()

      service_request =
        insert(:service_request,
          used_by_employee: build(:reference),
          used_by_legal_entity:
            build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(client_id))),
          code:
            build(:reference,
              identifier:
                build(:identifier,
                  type: codeable_concept_coding(code: "service_group"),
                  value: Mongo.string_to_uuid(service_group_id)
                )
            )
        )

      start_datetime =
        DateTime.utc_now()
        |> DateTime.to_unix()
        |> Kernel.-(100_000)
        |> DateTime.from_unix!()
        |> DateTime.to_iso8601()

      end_datetime = DateTime.to_iso8601(DateTime.utc_now())

      signed_content = %{
        "observations" => [
          %{
            "id" => observation_id,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "diagnostic_report" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                "value" => diagnostic_report_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{
              "coding" => [
                %{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"},
                %{"code" => "B70", "system" => "eHealth/LOINC/observation_codes"}
              ]
            },
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "interpretation" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/observation_interpretations"}]
            },
            "body_site" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/body_sites"}]
            },
            "method" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/observation_methods"}]
            },
            "value_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "reference_ranges" => [
              %{
                "type" => %{"coding" => [%{"code" => "category", "system" => "eHealth/reference_range_types"}]},
                "applies_to" => [
                  %{
                    "coding" => [%{"code" => "category", "system" => "eHealth/reference_range_applications"}]
                  }
                ]
              }
            ],
            "components" => [
              %{
                "code" => %{
                  "coding" => [%{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"}]
                },
                "value_period" => %{
                  "start" => start_datetime,
                  "end" => end_datetime
                },
                "interpretation" => %{
                  "coding" => [%{"code" => "1", "system" => "eHealth/observation_interpretations"}]
                },
                "reference_ranges" => [
                  %{
                    "applies_to" => [
                      %{
                        "coding" => [%{"code" => "category", "system" => "eHealth/reference_range_applications"}]
                      }
                    ]
                  }
                ]
              }
            ],
            "reaction_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "immunization"
                    }
                  ]
                },
                "value" => immunization_id
              }
            }
          },
          %{
            "id" => observation_id2,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "diagnostic_report" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                "value" => diagnostic_report_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{"coding" => [%{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"}]},
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "reaction_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "immunization"
                    }
                  ]
                },
                "value" => db_immunization_id
              }
            },
            "value_time" => "12:00:00"
          }
        ],
        "diagnostic_report" => %{
          "id" => diagnostic_report_id,
          "based_on" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service_request"
                  }
                ]
              },
              "value" => to_string(service_request._id)
            }
          },
          "status" => "final",
          "category" => [
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "LAB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            }
          ],
          "code" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service"
                  }
                ]
              },
              "value" => service_id
            }
          },
          "effective_period" => %{
            "start" => "2018-08-02T10:45:16.000Z",
            "end" => "2018-08-02T11:00:00.000Z"
          },
          "issued" => "2018-10-08T09:46:37.694Z",
          "conclusion" => "At risk of osteoporotic fracture",
          "conclusion_code" => %{
            "coding" => [
              %{
                "system" => "eHealth/SNOMED/clinical_findings",
                "code" => "109006"
              }
            ]
          },
          "recorded_by" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "employee"
                  }
                ]
              },
              "value" => employee_id
            }
          },
          "primary_source" => true,
          "managing_organization" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "legal_entity"
                  }
                ]
              },
              "value" => client_id
            }
          },
          "performer" => %{
            "reference" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "employee"
                    }
                  ]
                },
                "value" => employee_id
              }
            }
          },
          "results_interpreter" => %{
            "reference" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "employee"
                    }
                  ]
                },
                "value" => employee_id
              }
            }
          }
        }
      }

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.diagnostic_report.based_on.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Service request category should be equal to service category",
                  "params" => [],
                  "rule" => nil
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
               Consumer.consume(%DiagnosticReportPackageCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end

    test "service referenced in diagnostic report should belong to service group" do
      client_id = UUID.uuid4()
      user_id = UUID.uuid4()
      expect_signature(@drfo)
      expect_employee_users(@drfo, user_id)
      expect_doctor(client_id)

      expect(WorkerMock, :run, fn
        _, _, :service_by_id, _ -> {:ok, %{category: "counselling"}}
      end)

      expect_doctor(client_id)

      expect(WorkerMock, :run, fn
        _, _, :service_belongs_to_group?, _ -> false
      end)

      expect(IlMock, :get_legal_entity, fn id, _ ->
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

      episode =
        build(
          :episode,
          managing_organization:
            build(
              :reference,
              identifier:
                build(
                  :identifier,
                  type: build(:codeable_concept, coding: [build(:coding)]),
                  value: Mongo.string_to_uuid(client_id)
                )
            )
        )

      db_immunization_id = UUID.uuid4()
      immunization = build(:immunization, id: Mongo.string_to_uuid(db_immunization_id), reactions: [build(:reaction)])

      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))

      insert(
        :patient,
        _id: patient_id_hash,
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter},
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        immunizations: %{db_immunization_id => immunization}
      )

      insert(:observation, patient_id: patient_id_hash)
      immunization_id = UUID.uuid4()
      job = insert(:job)
      observation_id = UUID.uuid4()
      observation_id2 = UUID.uuid4()
      employee_id = UUID.uuid4()
      diagnostic_report_id = UUID.uuid4()
      service_id = UUID.uuid4()
      service_group_id = UUID.uuid4()

      service_request =
        insert(:service_request,
          used_by_employee: build(:reference),
          used_by_legal_entity:
            build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(client_id))),
          code:
            build(:reference,
              identifier:
                build(:identifier,
                  type: codeable_concept_coding(code: "service_group"),
                  value: Mongo.string_to_uuid(service_group_id)
                )
            )
        )

      start_datetime =
        DateTime.utc_now()
        |> DateTime.to_unix()
        |> Kernel.-(100_000)
        |> DateTime.from_unix!()
        |> DateTime.to_iso8601()

      end_datetime = DateTime.to_iso8601(DateTime.utc_now())

      signed_content = %{
        "observations" => [
          %{
            "id" => observation_id,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "diagnostic_report" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                "value" => diagnostic_report_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{
              "coding" => [
                %{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"},
                %{"code" => "B70", "system" => "eHealth/LOINC/observation_codes"}
              ]
            },
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "interpretation" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/observation_interpretations"}]
            },
            "body_site" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/body_sites"}]
            },
            "method" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/observation_methods"}]
            },
            "value_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "reference_ranges" => [
              %{
                "type" => %{"coding" => [%{"code" => "category", "system" => "eHealth/reference_range_types"}]},
                "applies_to" => [
                  %{
                    "coding" => [%{"code" => "category", "system" => "eHealth/reference_range_applications"}]
                  }
                ]
              }
            ],
            "components" => [
              %{
                "code" => %{
                  "coding" => [%{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"}]
                },
                "value_period" => %{
                  "start" => start_datetime,
                  "end" => end_datetime
                },
                "interpretation" => %{
                  "coding" => [%{"code" => "1", "system" => "eHealth/observation_interpretations"}]
                },
                "reference_ranges" => [
                  %{
                    "applies_to" => [
                      %{
                        "coding" => [%{"code" => "category", "system" => "eHealth/reference_range_applications"}]
                      }
                    ]
                  }
                ]
              }
            ],
            "reaction_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "immunization"
                    }
                  ]
                },
                "value" => immunization_id
              }
            }
          },
          %{
            "id" => observation_id2,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "diagnostic_report" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                "value" => diagnostic_report_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{"coding" => [%{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"}]},
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "reaction_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "immunization"
                    }
                  ]
                },
                "value" => db_immunization_id
              }
            },
            "value_time" => "12:00:00"
          }
        ],
        "diagnostic_report" => %{
          "id" => diagnostic_report_id,
          "based_on" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service_request"
                  }
                ]
              },
              "value" => to_string(service_request._id)
            }
          },
          "status" => "final",
          "category" => [
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "LAB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            }
          ],
          "code" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service"
                  }
                ]
              },
              "value" => service_id
            }
          },
          "effective_period" => %{
            "start" => "2018-08-02T10:45:16.000Z",
            "end" => "2018-08-02T11:00:00.000Z"
          },
          "issued" => "2018-10-08T09:46:37.694Z",
          "conclusion" => "At risk of osteoporotic fracture",
          "conclusion_code" => %{
            "coding" => [
              %{
                "system" => "eHealth/SNOMED/clinical_findings",
                "code" => "109006"
              }
            ]
          },
          "recorded_by" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "employee"
                  }
                ]
              },
              "value" => employee_id
            }
          },
          "primary_source" => true,
          "managing_organization" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "legal_entity"
                  }
                ]
              },
              "value" => client_id
            }
          },
          "performer" => %{
            "reference" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "employee"
                    }
                  ]
                },
                "value" => employee_id
              }
            }
          },
          "results_interpreter" => %{
            "reference" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "employee"
                    }
                  ]
                },
                "value" => employee_id
              }
            }
          }
        }
      }

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.diagnostic_report.based_on.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Service referenced in diagnostic report should belong to service group",
                  "params" => [],
                  "rule" => nil
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
               Consumer.consume(%DiagnosticReportPackageCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end

    test "service request should reference the same service that is referenced in diagnostic report" do
      client_id = UUID.uuid4()
      user_id = UUID.uuid4()
      expect_signature(@drfo)
      expect_employee_users(@drfo, user_id)
      expect_doctor(client_id)

      expect(WorkerMock, :run, fn
        _, _, :service_by_id, _ -> {:ok, %{category: "counselling"}}
      end)

      expect_doctor(client_id)

      expect(IlMock, :get_legal_entity, fn id, _ ->
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

      episode =
        build(
          :episode,
          managing_organization:
            build(
              :reference,
              identifier:
                build(
                  :identifier,
                  type: build(:codeable_concept, coding: [build(:coding)]),
                  value: Mongo.string_to_uuid(client_id)
                )
            )
        )

      db_immunization_id = UUID.uuid4()
      immunization = build(:immunization, id: Mongo.string_to_uuid(db_immunization_id), reactions: [build(:reaction)])

      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))

      insert(
        :patient,
        _id: patient_id_hash,
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter},
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        immunizations: %{db_immunization_id => immunization}
      )

      insert(:observation, patient_id: patient_id_hash)
      immunization_id = UUID.uuid4()
      job = insert(:job)
      observation_id = UUID.uuid4()
      observation_id2 = UUID.uuid4()
      employee_id = UUID.uuid4()
      diagnostic_report_id = UUID.uuid4()
      service_id = UUID.uuid4()

      service_request =
        insert(:service_request,
          used_by_employee: build(:reference),
          used_by_legal_entity:
            build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(client_id))),
          code:
            build(:reference,
              identifier:
                build(:identifier,
                  type: codeable_concept_coding(code: "service"),
                  value: Mongo.string_to_uuid(UUID.uuid4())
                )
            )
        )

      start_datetime =
        DateTime.utc_now()
        |> DateTime.to_unix()
        |> Kernel.-(100_000)
        |> DateTime.from_unix!()
        |> DateTime.to_iso8601()

      end_datetime = DateTime.to_iso8601(DateTime.utc_now())

      signed_content = %{
        "observations" => [
          %{
            "id" => observation_id,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "diagnostic_report" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                "value" => diagnostic_report_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{
              "coding" => [
                %{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"},
                %{"code" => "B70", "system" => "eHealth/LOINC/observation_codes"}
              ]
            },
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "interpretation" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/observation_interpretations"}]
            },
            "body_site" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/body_sites"}]
            },
            "method" => %{
              "coding" => [%{"code" => "1", "system" => "eHealth/observation_methods"}]
            },
            "value_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "reference_ranges" => [
              %{
                "type" => %{"coding" => [%{"code" => "category", "system" => "eHealth/reference_range_types"}]},
                "applies_to" => [
                  %{
                    "coding" => [%{"code" => "category", "system" => "eHealth/reference_range_applications"}]
                  }
                ]
              }
            ],
            "components" => [
              %{
                "code" => %{
                  "coding" => [%{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"}]
                },
                "value_period" => %{
                  "start" => start_datetime,
                  "end" => end_datetime
                },
                "interpretation" => %{
                  "coding" => [%{"code" => "1", "system" => "eHealth/observation_interpretations"}]
                },
                "reference_ranges" => [
                  %{
                    "applies_to" => [
                      %{
                        "coding" => [%{"code" => "category", "system" => "eHealth/reference_range_applications"}]
                      }
                    ]
                  }
                ]
              }
            ],
            "reaction_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "immunization"
                    }
                  ]
                },
                "value" => immunization_id
              }
            }
          },
          %{
            "id" => observation_id2,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "diagnostic_report" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "diagnostic_report", "system" => "eHealth/resources"}]},
                "value" => diagnostic_report_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{"coding" => [%{"code" => "8310-5", "system" => "eHealth/LOINC/observation_codes"}]},
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "reaction_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "immunization"
                    }
                  ]
                },
                "value" => db_immunization_id
              }
            },
            "value_time" => "12:00:00"
          }
        ],
        "diagnostic_report" => %{
          "id" => diagnostic_report_id,
          "based_on" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service_request"
                  }
                ]
              },
              "value" => to_string(service_request._id)
            }
          },
          "status" => "final",
          "category" => [
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "LAB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            },
            %{
              "coding" => [
                %{
                  "system" => "eHealth/diagnostic_report_categories",
                  "code" => "MB"
                }
              ]
            }
          ],
          "code" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "service"
                  }
                ]
              },
              "value" => service_id
            }
          },
          "effective_period" => %{
            "start" => "2018-08-02T10:45:16.000Z",
            "end" => "2018-08-02T11:00:00.000Z"
          },
          "issued" => "2018-10-08T09:46:37.694Z",
          "conclusion" => "At risk of osteoporotic fracture",
          "conclusion_code" => %{
            "coding" => [
              %{
                "system" => "eHealth/SNOMED/clinical_findings",
                "code" => "109006"
              }
            ]
          },
          "recorded_by" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "employee"
                  }
                ]
              },
              "value" => employee_id
            }
          },
          "primary_source" => true,
          "managing_organization" => %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "legal_entity"
                  }
                ]
              },
              "value" => client_id
            }
          },
          "performer" => %{
            "reference" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "employee"
                    }
                  ]
                },
                "value" => employee_id
              }
            }
          },
          "results_interpreter" => %{
            "reference" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "employee"
                    }
                  ]
                },
                "value" => employee_id
              }
            }
          }
        }
      }

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.diagnostic_report.based_on.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Should reference the same service that is referenced in diagnostic report",
                  "params" => [],
                  "rule" => nil
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
               Consumer.consume(%DiagnosticReportPackageCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end
  end
end
