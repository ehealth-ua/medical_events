defmodule Core.Kafka.Consumer.CreatePackageTest do
  @moduledoc false

  use Core.ModelCase

  import Core.Expectations.DigitalSignatureExpectation
  import Core.Expectations.IlExpectations
  import Mox

  alias Core.Immunization
  alias Core.Job
  alias Core.Jobs.PackageCreateJob
  alias Core.Kafka.Consumer
  alias Core.Mongo
  alias Core.Observation
  alias Core.Patients

  @status_valid Observation.status(:valid)
  @drfo "1111111111"

  setup :verify_on_exit!

  describe "consume create package event" do
    test "empty content" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

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
               Consumer.consume(%PackageCreateJob{
                 _id: to_string(job._id),
                 visit: %{"id" => UUID.uuid4(), "period" => %{}},
                 signed_data: Base.encode64(""),
                 user_id: user_id,
                 client_id: UUID.uuid4()
               })
    end

    test "empty map" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      job = insert(:job)
      user_id = UUID.uuid4()
      expect_signature(@drfo)

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.encounter",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "required property encounter was not present",
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
               Consumer.consume(%PackageCreateJob{
                 _id: to_string(job._id),
                 visit: %{"id" => UUID.uuid4(), "period" => %{}},
                 signed_data: Base.encode64(Jason.encode!(%{})),
                 user_id: user_id,
                 client_id: UUID.uuid4()
               })
    end

    test "visit not found" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      expect_doctor(client_id)

      expect(IlMock, :get_division, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "ACTIVE",
             "legal_entity_id" => client_id
           }
         }}
      end)

      encounter_id = UUID.uuid4()

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

      patient =
        insert(:patient, _id: patient_id_hash, episodes: %{UUID.binary_to_string!(episode.id.binary) => episode})

      condition = insert(:condition, patient_id: patient_id_hash)
      job = insert(:job)
      user_id = UUID.uuid4()
      expect_signature(@drfo)
      expect_employee_users(@drfo, user_id)
      episode_id = patient.episodes |> Map.keys() |> hd

      signed_content = %{
        "encounter" => %{
          "id" => encounter_id,
          "status" => "finished",
          "date" => DateTime.to_iso8601(DateTime.utc_now()),
          "visit" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "visit", "system" => "eHealth/resources"}]},
              "value" => UUID.uuid4()
            }
          },
          "episode" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          "class" => %{"code" => "AMB", "system" => "eHealth/encounter_classes"},
          "type" => %{"coding" => [%{"code" => "AMB", "system" => "eHealth/encounter_types"}]},
          "reasons" => [
            %{"coding" => [%{"code" => "reason", "system" => "eHealth/ICPC2/reasons"}]}
          ],
          "diagnoses" => [
            %{
              "condition" => %{
                "identifier" => %{
                  "type" => %{"coding" => [%{"code" => "condition", "system" => "eHealth/resources"}]},
                  "value" => UUID.binary_to_string!(condition._id.binary)
                }
              },
              "role" => %{"coding" => [%{"code" => "primary", "system" => "eHealth/diagnosis_roles"}]},
              "rank" => 10
            }
          ],
          "actions" => [%{"coding" => [%{"code" => "action", "system" => "eHealth/ICPC2/actions"}]}],
          "division" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "division", "system" => "eHealth/resources"}]},
              "value" => UUID.uuid4()
            }
          },
          "performer" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
              "value" => UUID.uuid4()
            }
          },
          "prescriptions" => "Дієта №1"
        }
      }

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.encounter.visit.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Visit with such ID is not found",
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
               Consumer.consume(%PackageCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end

    test "success create package" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      expect(MediaStorageMock, :save, fn _, _, _, _ -> :ok end)
      client_id = UUID.uuid4()
      user_id = UUID.uuid4()
      expect_signature(@drfo)
      expect_employee_users(@drfo, user_id)

      expect(WorkerMock, :run, fn
        _, _, :service_by_id, _ -> {:ok, %{category: "category"}}
      end)

      expect_doctor(client_id, 2)

      expect(IlMock, :get_division, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "ACTIVE",
             "legal_entity_id" => client_id
           }
         }}
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

      encounter_id = UUID.uuid4()

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      expect(WorkerMock, :run, fn
        _, _, :medication_request_by_id, [id] ->
          %{
            id: id,
            person_id: patient_id
          }
      end)

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

      patient =
        insert(
          :patient,
          _id: patient_id_hash,
          episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
          immunizations: %{db_immunization_id => immunization}
        )

      db_observation = insert(:observation, patient_id: patient_id_hash)
      condition_id = UUID.uuid4()
      immunization_id = UUID.uuid4()
      immunization_id2 = UUID.uuid4()
      job = insert(:job)
      visit_id = UUID.uuid4()
      episode_id = patient.episodes |> Map.keys() |> hd()
      observation_id = UUID.uuid4()
      observation_id2 = UUID.uuid4()
      employee_id = UUID.uuid4()
      allergy_intolerance_id = UUID.uuid4()
      risk_assessment_id = UUID.uuid4()
      device_id = UUID.uuid4()
      medication_statement_id = UUID.uuid4()
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
        "encounter" => %{
          "id" => encounter_id,
          "status" => "finished",
          "date" => DateTime.to_iso8601(DateTime.utc_now()),
          "visit" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "visit", "system" => "eHealth/resources"}]},
              "value" => visit_id
            }
          },
          "episode" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          "class" => %{"code" => "PHC", "system" => "eHealth/encounter_classes"},
          "type" => %{"coding" => [%{"code" => "AMB", "system" => "eHealth/encounter_types"}]},
          "reasons" => [
            %{"coding" => [%{"code" => "reason", "system" => "eHealth/ICPC2/reasons"}]}
          ],
          "diagnoses" => [
            %{
              "condition" => %{
                "identifier" => %{
                  "type" => %{"coding" => [%{"code" => "condition", "system" => "eHealth/resources"}]},
                  "value" => condition_id
                }
              },
              "role" => %{"coding" => [%{"code" => "primary", "system" => "eHealth/diagnosis_roles"}]}
            }
          ],
          "actions" => [%{"coding" => [%{"code" => "action", "system" => "eHealth/ICPC2/actions"}]}],
          "division" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "division", "system" => "eHealth/resources"}]},
              "value" => UUID.uuid4()
            }
          },
          "performer" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
              "value" => employee_id
            }
          },
          "prescriptions" => "Дієта №1",
          "incoming_referrals" => [
            %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                "value" => to_string(service_request._id)
              }
            }
          ],
          "supporting_info" => [
            %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "observation", "system" => "eHealth/resources"}]},
                "value" => UUID.binary_to_string!(db_observation._id.binary)
              }
            }
          ]
        },
        "conditions" => [
          %{
            "id" => condition_id,
            "context" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                "value" => encounter_id
              }
            },
            "code" => %{"coding" => [%{"code" => "R80", "system" => "eHealth/ICPC2/condition_codes"}]},
            "clinical_status" => "test",
            "verification_status" => "test",
            "onset_date" => DateTime.to_iso8601(DateTime.utc_now()),
            "severity" => %{"coding" => [%{"code" => "1", "system" => "eHealth/condition_severities"}]},
            "body_sites" => [%{"coding" => [%{"code" => "1", "system" => "eHealth/body_sites"}]}],
            "stage" => %{
              "summary" => %{"coding" => [%{"code" => "1", "system" => "eHealth/condition_stages"}]}
            },
            "evidences" => [
              %{
                "codes" => [%{"coding" => [%{"code" => "A02", "system" => "eHealth/ICPC2/reasons"}]}],
                "details" => [
                  %{
                    "identifier" => %{
                      "type" => %{"coding" => [%{"code" => "observation", "system" => "eHealth/resources"}]},
                      "value" => observation_id
                    }
                  },
                  %{
                    "identifier" => %{
                      "type" => %{"coding" => [%{"code" => "observation", "system" => "eHealth/resources"}]},
                      "value" => UUID.binary_to_string!(db_observation._id.binary)
                    }
                  }
                ]
              }
            ],
            "primary_source" => true,
            "asserter" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            }
          }
        ],
        "observations" => [
          %{
            "id" => observation_id,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "context" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                "value" => encounter_id
              }
            },
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
            "context" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                "value" => encounter_id
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
            "primary_source" => false,
            "report_origin" => %{
              "coding" => [%{"code" => "employee", "system" => "eHealth/report_origins"}]
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
        "immunizations" => [
          %{
            "id" => immunization_id,
            "status" => Immunization.status(:completed),
            "not_given" => false,
            "vaccine_code" => %{
              "coding" => [
                %{
                  "system" => "eHealth/vaccine_codes",
                  "code" => "FLUVAX"
                }
              ]
            },
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
              }
            },
            "report_origin" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/report_origins"}]},
            "primary_source" => false,
            "date" => DateTime.to_iso8601(DateTime.utc_now()),
            "site" => %{"coding" => [%{"code" => "1", "system" => "eHealth/body_sites"}]},
            "route" => %{"coding" => [%{"code" => "IM", "system" => "eHealth/vaccination_routes"}]},
            "dose_quantity" => %{
              "value" => 18,
              "unit" => "mg",
              "system" => "eHealth/ucum/units"
            },
            "explanation" => %{
              "reasons" => [
                %{
                  "coding" => [
                    %{
                      "system" => "eHealth/reason_explanations",
                      "code" => "429060002"
                    }
                  ]
                }
              ]
            },
            "vaccination_protocols" => [
              %{
                "dose_sequence" => 1,
                "description" => "Vaccination Protocol Sequence 1",
                "authority" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/vaccination_authorities",
                      "code" => "1857005"
                    }
                  ]
                },
                "series" => "Vaccination Series 1",
                "series_doses" => 2,
                "target_diseases" => [
                  %{
                    "coding" => [
                      %{
                        "system" => "eHealth/vaccination_target_diseases",
                        "code" => "1857005"
                      }
                    ]
                  }
                ]
              }
            ]
          },
          %{
            "id" => immunization_id2,
            "status" => Immunization.status(:completed),
            "not_given" => false,
            "vaccine_code" => %{
              "coding" => [
                %{
                  "system" => "eHealth/vaccine_codes",
                  "code" => "FLUVAX"
                }
              ]
            },
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
              }
            },
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "primary_source" => true,
            "date" => DateTime.to_iso8601(DateTime.utc_now()),
            "site" => %{"coding" => [%{"code" => "1", "system" => "eHealth/body_sites"}]},
            "route" => %{"coding" => [%{"code" => "IM", "system" => "eHealth/vaccination_routes"}]},
            "dose_quantity" => %{
              "value" => 18,
              "unit" => "mg",
              "system" => "eHealth/ucum/units"
            },
            "explanation" => %{
              "reasons" => [
                %{
                  "coding" => [
                    %{
                      "system" => "eHealth/reason_explanations",
                      "code" => "429060002"
                    }
                  ]
                }
              ]
            }
          }
        ],
        "allergy_intolerances" => [
          %{
            "id" => allergy_intolerance_id,
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
              }
            },
            "code" => %{
              "coding" => [
                %{
                  "system" => "eHealth/allergy_intolerance_codes",
                  "code" => "227493005"
                }
              ]
            },
            "report_origin" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/report_origins"}]},
            "primary_source" => false,
            "clinical_status" => "active",
            "verification_status" => "confirmed",
            "type" => "allergy",
            "category" => "food",
            "criticality" => "low",
            "asserted_date" => DateTime.to_iso8601(DateTime.utc_now()),
            "last_occurrence" => DateTime.to_iso8601(DateTime.utc_now()),
            "onset_date_time" => DateTime.to_iso8601(DateTime.utc_now())
          }
        ],
        "risk_assessments" => [
          %{
            "id" => risk_assessment_id,
            "status" => "preliminary",
            "method" => %{
              "coding" => [
                %{
                  "system" => "eHealth/risk_assessment_methods",
                  "code" => "default_code"
                }
              ]
            },
            "code" => %{
              "coding" => [
                %{
                  "system" => "eHealth/risk_assessment_codes",
                  "code" => "default_risk_assessment_code"
                }
              ]
            },
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
              }
            },
            "asserted_date" => DateTime.to_iso8601(DateTime.utc_now()),
            "performer" => %{
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
            "reason_references" => [
              %{
                "identifier" => %{
                  "type" => %{
                    "coding" => [
                      %{
                        "system" => "eHealth/resources",
                        "code" => "observation"
                      }
                    ]
                  },
                  "value" => UUID.binary_to_string!(db_observation._id.binary)
                }
              }
            ],
            "basis" => %{
              "references" => [
                %{
                  "identifier" => %{
                    "type" => %{
                      "coding" => [
                        %{
                          "system" => "eHealth/resources",
                          "code" => "observation"
                        }
                      ]
                    },
                    "value" => UUID.binary_to_string!(db_observation._id.binary)
                  }
                },
                %{
                  "identifier" => %{
                    "type" => %{
                      "coding" => [
                        %{
                          "system" => "eHealth/resources",
                          "code" => "condition"
                        }
                      ]
                    },
                    "value" => condition_id
                  }
                }
              ],
              "text" => "basis"
            },
            "predictions" => [
              %{
                "outcome" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/risk_assessment_outcomes",
                      "code" => "default_outcome"
                    }
                  ]
                },
                "qualitative_risk" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/risk_assessment_qualitative_risks",
                      "code" => "default_qualitative_risk"
                    }
                  ]
                },
                "when_period" => %{
                  "start" => start_datetime,
                  "end" => end_datetime
                },
                "rationale" => "some text"
              }
            ],
            "mitigation" => "some text",
            "comment" => "some text"
          }
        ],
        "devices" => [
          %{
            "id" => device_id,
            "status" => "inactive",
            "asserted_date" => DateTime.to_iso8601(DateTime.utc_now()),
            "usage_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
              }
            },
            "primary_source" => true,
            "asserter" => %{
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
            "type" => %{
              "coding" => [
                %{
                  "system" => "eHealth/device_types",
                  "code" => "Spine_board"
                }
              ]
            },
            "lot_number" => "RZ12345678",
            "manufacturer" => "GlobalMed, Inc",
            "manufacture_date" => DateTime.to_iso8601(DateTime.utc_now()),
            "expiration_date" => DateTime.to_iso8601(DateTime.utc_now()),
            "model" => "NSPX30",
            "version" => "v1.0.1",
            "note" => "Імплант був вилучений по причині заміни на новий"
          }
        ],
        "medication_statements" => [
          %{
            "id" => medication_statement_id,
            "based_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "medication_request"
                    }
                  ]
                },
                "value" => UUID.uuid4()
              }
            },
            "asserted_date" => "2018-08-02T10:45:00.000Z",
            "status" => "active",
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
              }
            },
            "primary_source" => true,
            "asserter" => %{
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
            "effective_period" => "Вживає з 2017-го року регулярно",
            "medication_code" => %{
              "coding" => [
                %{
                  "system" => "eHealth/medication_statement_medications",
                  "code" => "Spine_board"
                }
              ]
            },
            "note" => "Some text",
            "dosage" => "5 ml/day"
          }
        ],
        "diagnostic_reports" => [
          %{
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
            "encounter" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
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
        ]
      }

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert [
                 %{"collection" => "patients", "operation" => "update_one", "set" => patient_data},
                 %{"collection" => "conditions", "operation" => "insert"},
                 %{"collection" => "observations", "operation" => "insert"},
                 %{"collection" => "observations", "operation" => "insert"},
                 %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
               ] = Jason.decode!(args)

        patient_data = patient_data |> Base.decode64!() |> BSON.decode()

        assert observation_id ==
                 patient_data["$set"]["immunizations.#{immunization_id}.reactions"]
                 |> hd()
                 |> get_in(~w(detail identifier value))
                 |> to_string()

        assert observation_id2 ==
                 patient_data["$set"]["immunizations.#{db_immunization_id}.reactions"]
                 |> Enum.at(1)
                 |> get_in(~w(detail identifier value))
                 |> to_string()

        assert 2 == length(patient_data["$set"]["immunizations.#{db_immunization_id}.reactions"])
        assert patient_data["$set"]["immunizations.#{immunization_id}.reactions"]
        assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

        set_bson = set |> Base.decode64!() |> BSON.decode()
        status = Job.status(:processed)

        response = %{
          "links" => [
            %{
              "entity" => "encounter",
              "href" => "/api/patients/#{patient_id}/encounters/#{encounter_id}"
            },
            %{
              "entity" => "immunization",
              "href" => "/api/patients/#{patient_id}/immunizations/#{immunization_id}"
            },
            %{
              "entity" => "immunization",
              "href" => "/api/patients/#{patient_id}/immunizations/#{immunization_id2}"
            },
            %{
              "entity" => "immunization",
              "href" => "/api/patients/#{patient_id}/immunizations/#{db_immunization_id}"
            },
            %{
              "entity" => "allergy_intolerance",
              "href" => "/api/patients/#{patient_id}/allergy_intolerances/#{allergy_intolerance_id}"
            },
            %{
              "entity" => "risk_assessment",
              "href" => "/api/patients/#{patient_id}/risk_assessments/#{risk_assessment_id}"
            },
            %{
              "entity" => "device",
              "href" => "/api/patients/#{patient_id}/devices/#{device_id}"
            },
            %{
              "entity" => "medication_statement",
              "href" => "/api/patients/#{patient_id}/medication_statements/#{medication_statement_id}"
            },
            %{
              "entity" => "diagnostic_report",
              "href" => "/api/patients/#{patient_id}/diagnostic_reports/#{diagnostic_report_id}"
            },
            %{
              "entity" => "condition",
              "href" => "/api/patients/#{patient_id}/conditions/#{condition_id}"
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
               Consumer.consume(%PackageCreateJob{
                 _id: to_string(job._id),
                 visit: %{
                   "id" => visit_id,
                   "period" => %{
                     "start" => start_datetime,
                     "end" => end_datetime
                   }
                 },
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end

    test "failed when encounter reference episode doesnt match episode managing organization" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      client_id = UUID.uuid4()
      expect_doctor(client_id)

      expect(IlMock, :get_division, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "ACTIVE",
             "legal_entity_id" => client_id
           }
         }}
      end)

      encounter_id = UUID.uuid4()

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient = insert(:patient, _id: patient_id_hash)
      db_observation = insert(:observation, patient_id: patient_id_hash)
      condition_id = UUID.uuid4()
      job = insert(:job)
      user_id = UUID.uuid4()
      expect_signature(@drfo)
      expect_employee_users(@drfo, user_id)
      visit_id = UUID.uuid4()
      episode_id = patient.episodes |> Map.keys() |> hd()
      observation_id = UUID.uuid4()
      employee_id = UUID.uuid4()

      start_datetime =
        DateTime.utc_now()
        |> DateTime.to_unix()
        |> Kernel.-(100_000)
        |> DateTime.from_unix!()
        |> DateTime.to_iso8601()

      end_datetime = DateTime.to_iso8601(DateTime.utc_now())

      signed_content = %{
        "encounter" => %{
          "id" => encounter_id,
          "status" => "finished",
          "date" => DateTime.to_iso8601(DateTime.utc_now()),
          "visit" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "visit", "system" => "eHealth/resources"}]},
              "value" => visit_id
            }
          },
          "episode" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          "class" => %{"code" => "AMB", "system" => "eHealth/encounter_classes"},
          "type" => %{"coding" => [%{"code" => "AMB", "system" => "eHealth/encounter_types"}]},
          "reasons" => [
            %{"coding" => [%{"code" => "reason", "system" => "eHealth/ICPC2/reasons"}]}
          ],
          "diagnoses" => [
            %{
              "condition" => %{
                "identifier" => %{
                  "type" => %{"coding" => [%{"code" => "condition", "system" => "eHealth/resources"}]},
                  "value" => condition_id
                }
              },
              "role" => %{"coding" => [%{"code" => "primary", "system" => "eHealth/diagnosis_roles"}]}
            }
          ],
          "actions" => [%{"coding" => [%{"code" => "action", "system" => "eHealth/ICPC2/actions"}]}],
          "division" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "division", "system" => "eHealth/resources"}]},
              "value" => UUID.uuid4()
            }
          },
          "performer" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
              "value" => employee_id
            }
          },
          "prescriptions" => "Дієта №1"
        },
        "conditions" => [
          %{
            "id" => condition_id,
            "context" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                "value" => encounter_id
              }
            },
            "code" => %{"coding" => [%{"code" => "A10", "system" => "eHealth/ICD10/condition_codes"}]},
            "clinical_status" => "test",
            "verification_status" => "test",
            "onset_date" => DateTime.to_iso8601(DateTime.utc_now()),
            "severity" => %{"coding" => [%{"code" => "1", "system" => "eHealth/condition_severities"}]},
            "body_sites" => [%{"coding" => [%{"code" => "1", "system" => "eHealth/body_sites"}]}],
            "stage" => %{
              "summary" => %{"coding" => [%{"code" => "1", "system" => "eHealth/condition_stages"}]}
            },
            "evidences" => [
              %{
                "codes" => [%{"coding" => [%{"code" => "A02", "system" => "eHealth/ICPC2/reasons"}]}],
                "details" => [
                  %{
                    "identifier" => %{
                      "type" => %{"coding" => [%{"code" => "observation", "system" => "eHealth/resources"}]},
                      "value" => observation_id
                    }
                  },
                  %{
                    "identifier" => %{
                      "type" => %{"coding" => [%{"code" => "observation", "system" => "eHealth/resources"}]},
                      "value" => UUID.binary_to_string!(db_observation._id.binary)
                    }
                  }
                ]
              }
            ],
            "primary_source" => false,
            "report_origin" => %{
              "coding" => [%{"code" => "employee", "system" => "eHealth/report_origins"}]
            }
          }
        ],
        "observations" => [
          %{
            "id" => observation_id,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "context" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                "value" => encounter_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{"coding" => [%{"code" => "8480-6", "system" => "eHealth/LOINC/observation_codes"}]},
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
            ]
          },
          %{
            "id" => UUID.uuid4(),
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "context" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                "value" => encounter_id
              }
            },
            "categories" => [
              %{"coding" => [%{"code" => "1", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{"coding" => [%{"code" => "8480-6", "system" => "eHealth/LOINC/observation_codes"}]},
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "primary_source" => false,
            "report_origin" => %{
              "coding" => [%{"code" => "employee", "system" => "eHealth/report_origins"}]
            },
            "value_time" => "12:00:00"
          }
        ],
        "immunizations" => [
          %{
            "id" => UUID.uuid4(),
            "status" => Immunization.status(:completed),
            "not_given" => false,
            "vaccine_code" => %{
              "coding" => [
                %{
                  "system" => "eHealth/vaccine_codes",
                  "code" => "FLUVAX"
                }
              ]
            },
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
              }
            },
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "primary_source" => true,
            "date" => DateTime.to_iso8601(DateTime.utc_now()),
            "site" => %{"coding" => [%{"code" => "1", "system" => "eHealth/body_sites"}]},
            "route" => %{"coding" => [%{"code" => "IM", "system" => "eHealth/vaccination_routes"}]},
            "dose_quantity" => %{
              "value" => 18,
              "unit" => "mg",
              "system" => "eHealth/ucum/units"
            },
            "explanation" => %{
              "reasons" => [
                %{
                  "coding" => [
                    %{
                      "system" => "eHealth/reason_explanations",
                      "code" => "429060002"
                    }
                  ]
                }
              ]
            },
            "vaccination_protocols" => [
              %{
                "dose_sequence" => 1,
                "description" => "Vaccination Protocol Sequence 1",
                "authority" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/vaccination_authorities",
                      "code" => "1857005"
                    }
                  ]
                },
                "series" => "Vaccination Series 1",
                "series_doses" => 2,
                "target_diseases" => [
                  %{
                    "coding" => [
                      %{
                        "system" => "eHealth/vaccination_target_diseases",
                        "code" => "1857005"
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ],
        "allergy_intolerances" => [
          %{
            "id" => UUID.uuid4(),
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
              }
            },
            "code" => %{
              "coding" => [
                %{
                  "system" => "eHealth/allergy_intolerance_codes",
                  "code" => "227493005"
                }
              ]
            },
            "asserter" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "primary_source" => true,
            "clinical_status" => "active",
            "verification_status" => "confirmed",
            "type" => "allergy",
            "category" => "food",
            "criticality" => "low",
            "asserted_date" => DateTime.to_iso8601(DateTime.utc_now()),
            "last_occurrence" => DateTime.to_iso8601(DateTime.utc_now()),
            "onset_date_time" => DateTime.to_iso8601(DateTime.utc_now())
          }
        ]
      }

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.encounter.episode.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Managing_organization does not correspond to user's legal_entity",
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
               Consumer.consume(%PackageCreateJob{
                 _id: to_string(job._id),
                 visit: %{
                   "id" => visit_id,
                   "period" => %{
                     "start" => start_datetime,
                     "end" => end_datetime
                   }
                 },
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

      encounter_id = UUID.uuid4()
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

      patient =
        insert(:patient, _id: patient_id_hash, episodes: %{UUID.binary_to_string!(episode.id.binary) => episode})

      condition_id = UUID.uuid4()
      insert(:condition, patient_id: patient_id_hash, _id: Mongo.string_to_uuid(condition_id))

      job = insert(:job)

      user_id = UUID.uuid4()
      expect_signature(nil)

      visit_id = UUID.uuid4()
      episode_id = patient.episodes |> Map.keys() |> hd()
      employee_id = UUID.uuid4()

      start_datetime =
        DateTime.utc_now()
        |> DateTime.to_unix()
        |> Kernel.-(100_000)
        |> DateTime.from_unix!()
        |> DateTime.to_iso8601()

      end_datetime = DateTime.to_iso8601(DateTime.utc_now())

      signed_content = %{
        "encounter" => %{
          "id" => encounter_id,
          "status" => "finished",
          "date" => DateTime.to_iso8601(DateTime.utc_now()),
          "visit" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "visit", "system" => "eHealth/resources"}]},
              "value" => visit_id
            }
          },
          "episode" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          "class" => %{"code" => "AMB", "system" => "eHealth/encounter_classes"},
          "type" => %{"coding" => [%{"code" => "AMB", "system" => "eHealth/encounter_types"}]},
          "reasons" => [
            %{"coding" => [%{"code" => "reason", "system" => "eHealth/ICPC2/reasons"}]}
          ],
          "diagnoses" => [
            %{
              "condition" => %{
                "identifier" => %{
                  "type" => %{"coding" => [%{"code" => "condition", "system" => "eHealth/resources"}]},
                  "value" => condition_id
                }
              },
              "role" => %{"coding" => [%{"code" => "primary", "system" => "eHealth/diagnosis_roles"}]}
            }
          ],
          "actions" => [%{"coding" => [%{"code" => "action", "system" => "eHealth/ICPC2/actions"}]}],
          "performer" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
              "value" => employee_id
            }
          },
          "prescriptions" => "Дієта №1"
        }
      }

      expect_job_update(job._id, Job.status(:failed), "Invalid drfo", 409)

      assert :ok =
               Consumer.consume(%PackageCreateJob{
                 _id: to_string(job._id),
                 visit: %{
                   "id" => visit_id,
                   "period" => %{
                     "start" => start_datetime,
                     "end" => end_datetime
                   }
                 },
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end

    test "invalid create package request params" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      encounter_id = UUID.uuid4()
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

      patient =
        insert(
          :patient,
          _id: patient_id_hash,
          episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
          immunizations: %{db_immunization_id => immunization}
        )

      db_observation = insert(:observation, patient_id: patient_id_hash)
      condition_id = UUID.uuid4()
      immunization_id = UUID.uuid4()
      immunization_id2 = UUID.uuid4()
      job = insert(:job)
      user_id = UUID.uuid4()
      expect_signature(@drfo)
      visit_id = UUID.uuid4()
      episode_id = patient.episodes |> Map.keys() |> hd()
      observation_id = UUID.uuid4()
      observation_id2 = UUID.uuid4()
      employee_id = UUID.uuid4()
      allergy_intolerance_id = UUID.uuid4()
      risk_assessment_id = UUID.uuid4()
      device_id = UUID.uuid4()
      medication_statement_id = UUID.uuid4()
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
        "encounter" => %{
          "id" => encounter_id,
          "status" => "finished",
          "date" => DateTime.to_iso8601(DateTime.utc_now()),
          "visit" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "visit", "system" => "eHealth/resources"}]},
              "value" => visit_id
            }
          },
          "episode" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          "class" => %{"code" => "PHC", "system" => "eHealth/encounter_classes"},
          "type" => %{"coding" => [%{"code" => "AMB", "system" => "eHealth/encounter_types"}]},
          "reasons" => [
            %{"coding" => [%{"code" => "reason", "system" => "eHealth/ICPC2/reasons"}]}
          ],
          "diagnoses" => [
            %{
              "condition" => %{
                "identifier" => %{
                  "type" => %{"coding" => [%{"code" => "condition", "system" => "eHealth/resources"}]},
                  "value" => condition_id
                }
              },
              "role" => %{"coding" => [%{"code" => "primary", "system" => "eHealth/diagnosis_roles"}]}
            }
          ],
          "actions" => [%{"coding" => [%{"code" => "action", "system" => "eHealth/ICPC2/actions"}]}],
          "division" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "division", "system" => "eHealth/resources"}]},
              "value" => UUID.uuid4()
            }
          },
          "performer" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
              "value" => employee_id
            }
          },
          "prescriptions" => "Дієта №1",
          "incoming_referrals" => [
            %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                "value" => to_string(service_request._id)
              }
            }
          ]
        },
        "conditions" => [
          %{
            "id" => condition_id,
            "context" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                "value" => encounter_id
              }
            },
            "code" => %{"coding" => [%{"code" => "R80", "system" => "eHealth/ICPC2/condition_codes"}]},
            "clinical_status" => "test",
            "verification_status" => "test",
            "onset_date" => DateTime.to_iso8601(DateTime.utc_now()),
            "severity" => %{"coding" => [%{"code" => "1", "system" => "eHealth/condition_severities"}]},
            "body_sites" => [%{"coding" => [%{"code" => "1", "system" => "eHealth/body_sites"}]}],
            "stage" => %{
              "summary" => %{"coding" => [%{"code" => "1", "system" => "eHealth/condition_stages"}]}
            },
            "evidences" => [
              %{
                "codes" => [%{"coding" => [%{"code" => "A02", "system" => "eHealth/ICPC2/reasons"}]}],
                "details" => [
                  %{
                    "identifier" => %{
                      "type" => %{"coding" => [%{"code" => "observation", "system" => "eHealth/resources"}]},
                      "value" => observation_id
                    }
                  },
                  %{
                    "identifier" => %{
                      "type" => %{"coding" => [%{"code" => "observation", "system" => "eHealth/resources"}]},
                      "value" => UUID.binary_to_string!(db_observation._id.binary)
                    }
                  }
                ]
              }
            ],
            "primary_source" => true,
            "asserter" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => employee_id
              }
            },
            "report_origin" => %{
              "coding" => [%{"code" => "employee", "system" => "eHealth/report_origins"}]
            }
          }
        ],
        "observations" => [
          %{
            "id" => observation_id,
            "status" => @status_valid,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "context" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                "value" => encounter_id
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
            "context" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                "value" => encounter_id
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
            "primary_source" => false,
            "report_origin" => %{
              "coding" => [%{"code" => "employee", "system" => "eHealth/report_origins"}]
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
        "immunizations" => [
          %{
            "id" => immunization_id,
            "status" => Immunization.status(:completed),
            "not_given" => false,
            "vaccine_code" => %{
              "coding" => [
                %{
                  "system" => "eHealth/vaccine_codes",
                  "code" => "FLUVAX"
                }
              ]
            },
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
              }
            },
            "report_origin" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/report_origins"}]},
            "primary_source" => false,
            "date" => DateTime.to_iso8601(DateTime.utc_now()),
            "site" => %{"coding" => [%{"code" => "1", "system" => "eHealth/body_sites"}]},
            "route" => %{"coding" => [%{"code" => "IM", "system" => "eHealth/vaccination_routes"}]},
            "dose_quantity" => %{
              "value" => 18,
              "unit" => "mg",
              "system" => "eHealth/ucum/units"
            },
            "explanation" => %{
              "reasons" => [
                %{
                  "coding" => [
                    %{
                      "system" => "eHealth/reason_explanations",
                      "code" => "429060002"
                    }
                  ]
                }
              ]
            },
            "vaccination_protocols" => [
              %{
                "dose_sequence" => 1,
                "description" => "Vaccination Protocol Sequence 1",
                "authority" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/vaccination_authorities",
                      "code" => "1857005"
                    }
                  ]
                },
                "series" => "Vaccination Series 1",
                "series_doses" => 2,
                "target_diseases" => [
                  %{
                    "coding" => [
                      %{
                        "system" => "eHealth/vaccination_target_diseases",
                        "code" => "1857005"
                      }
                    ]
                  }
                ]
              }
            ]
          },
          %{
            "id" => immunization_id2,
            "status" => Immunization.status(:completed),
            "not_given" => false,
            "vaccine_code" => %{
              "coding" => [
                %{
                  "system" => "eHealth/vaccine_codes",
                  "code" => "FLUVAX"
                }
              ]
            },
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
              }
            },
            "primary_source" => true,
            "date" => DateTime.to_iso8601(DateTime.utc_now()),
            "site" => %{"coding" => [%{"code" => "1", "system" => "eHealth/body_sites"}]},
            "route" => %{"coding" => [%{"code" => "IM", "system" => "eHealth/vaccination_routes"}]},
            "dose_quantity" => %{
              "value" => 18,
              "unit" => "mg",
              "system" => "eHealth/ucum/units"
            },
            "explanation" => %{
              "reasons" => [
                %{
                  "coding" => [
                    %{
                      "system" => "eHealth/reason_explanations",
                      "code" => "429060002"
                    }
                  ]
                }
              ],
              "reasons_not_given" => [
                %{
                  "coding" => [
                    %{
                      "system" => "eHealth/reason_not_given_explanations",
                      "code" => "429060002"
                    }
                  ]
                }
              ]
            }
          }
        ],
        "allergy_intolerances" => [
          %{
            "id" => allergy_intolerance_id,
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
              }
            },
            "code" => %{
              "coding" => [
                %{
                  "system" => "eHealth/allergy_intolerance_codes",
                  "code" => "227493005"
                }
              ]
            },
            "primary_source" => false,
            "clinical_status" => "active",
            "verification_status" => "confirmed",
            "type" => "allergy",
            "category" => "food",
            "criticality" => "low",
            "asserted_date" => DateTime.to_iso8601(DateTime.utc_now()),
            "last_occurrence" => DateTime.to_iso8601(DateTime.utc_now()),
            "onset_date_time" => DateTime.to_iso8601(DateTime.utc_now())
          }
        ],
        "risk_assessments" => [
          %{
            "id" => risk_assessment_id,
            "status" => "preliminary",
            "method" => %{
              "coding" => [
                %{
                  "system" => "eHealth/risk_assessment_methods",
                  "code" => "default_code"
                }
              ]
            },
            "code" => %{
              "coding" => [
                %{
                  "system" => "eHealth/risk_assessment_codes",
                  "code" => "default_risk_assessment_code"
                }
              ]
            },
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
              }
            },
            "asserted_date" => DateTime.to_iso8601(DateTime.utc_now()),
            "performer" => %{
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
            "reason_references" => [
              %{
                "identifier" => %{
                  "type" => %{
                    "coding" => [
                      %{
                        "system" => "eHealth/resources",
                        "code" => "observation"
                      }
                    ]
                  },
                  "value" => UUID.binary_to_string!(db_observation._id.binary)
                }
              }
            ],
            "basis" => %{
              "references" => [
                %{
                  "identifier" => %{
                    "type" => %{
                      "coding" => [
                        %{
                          "system" => "eHealth/resources",
                          "code" => "observation"
                        }
                      ]
                    },
                    "value" => UUID.binary_to_string!(db_observation._id.binary)
                  }
                },
                %{
                  "identifier" => %{
                    "type" => %{
                      "coding" => [
                        %{
                          "system" => "eHealth/resources",
                          "code" => "condition"
                        }
                      ]
                    },
                    "value" => condition_id
                  }
                }
              ],
              "text" => "basis"
            },
            "predictions" => [
              %{
                "outcome" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/risk_assessment_outcomes",
                      "code" => "default_outcome"
                    }
                  ]
                },
                "qualitative_risk" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/risk_assessment_qualitative_risks",
                      "code" => "default_qualitative_risk"
                    }
                  ]
                },
                "when_period" => %{
                  "start" => start_datetime,
                  "end" => end_datetime
                },
                "when_range" => %{
                  "high" => %{
                    "code" => "mg",
                    "comparator" => "<",
                    "system" => "eHealth/ucum/units",
                    "unit" => "hours",
                    "value" => 9
                  },
                  "low" => %{
                    "code" => "mg",
                    "comparator" => ">",
                    "system" => "eHealth/ucum/units",
                    "unit" => "hours",
                    "value" => 13
                  }
                },
                "rationale" => "some text"
              }
            ],
            "mitigation" => "some text",
            "comment" => "some text"
          }
        ],
        "devices" => [
          %{
            "id" => device_id,
            "status" => "inactive",
            "asserted_date" => DateTime.to_iso8601(DateTime.utc_now()),
            "usage_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
              }
            },
            "primary_source" => true,
            "type" => %{
              "coding" => [
                %{
                  "system" => "eHealth/device_types",
                  "code" => "Spine_board"
                }
              ]
            },
            "lot_number" => "RZ12345678",
            "manufacturer" => "GlobalMed, Inc",
            "manufacture_date" => DateTime.to_iso8601(DateTime.utc_now()),
            "expiration_date" => DateTime.to_iso8601(DateTime.utc_now()),
            "model" => "NSPX30",
            "version" => "v1.0.1",
            "note" => "Імплант був вилучений по причині заміни на новий"
          }
        ],
        "medication_statements" => [
          %{
            "id" => medication_statement_id,
            "based_on" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "medication_request"
                    }
                  ]
                },
                "value" => UUID.uuid4()
              }
            },
            "asserted_date" => "2018-08-02T10:45:00.000Z",
            "status" => "active",
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
              }
            },
            "primary_source" => true,
            "asserter" => %{
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
            "report_origin" => %{
              "coding" => [%{"code" => "employee", "system" => "eHealth/report_origins"}]
            },
            "effective_period" => "Вживає з 2017-го року регулярно",
            "medication_code" => %{
              "coding" => [
                %{
                  "system" => "eHealth/medication_statement_medications",
                  "code" => "Spine_board"
                }
              ]
            },
            "note" => "Some text",
            "dosage" => "5 ml/day"
          }
        ],
        "diagnostic_reports" => [
          %{
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
            "encounter" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/resources",
                      "code" => "encounter"
                    }
                  ]
                },
                "value" => encounter_id
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
        ]
      }

      # expected error results:
      #   conditions:
      #     "report_origin", "asserter": all OneOf parameters are sent
      #   observations:
      #     "report_origin", "performer": none of OneOf parameters are sent
      #     "effective_date_time", "effective_period": all OneOf parameters are sent
      #     "value_quantity", "value_codeable_concept", "value_sampled_data", "value_string", "value_boolean",
      #         "value_range", "value_ratio", "value_time", "value_date_time", "value_period": none of OneOf parameters are sent
      #     components:
      #       "value_quantity", "value_codeable_concept", "value_sampled_data", "value_string", "value_boolean",
      #           "value_range", "value_ratio", "value_time", "value_date_time", "value_period": more than one OneOf parameters are sent
      #   immunizations:
      #     "report_origin", "performer": none of OneOf parameters are sent
      #     explanation:
      #       "reasons", "reasons_not_given": all OneOf parameters are sent
      #   allergy_intolerances:
      #     "report_origin", "asserter": none of OneOf parameters are sent
      #   risk_assessments:
      #     predictions:
      #       "probability_range", "probability_decimal": none of OneOf parameters are sent (optional)
      #       "when_range", "when_period": all OneOf parameters are sent (optional)
      #   devices:
      #     "report_origin", "asserter": none of OneOf parameters are sent
      #   medication_statements:
      #     "report_origin", "asserter": all OneOf parameters are sent
      #   diagnostic_reports:
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
              "entry" => "$.allergy_intolerances[0]",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "At least one of the parameters must be present",
                  "params" => ["$.allergy_intolerances[0].report_origin", "$.allergy_intolerances[0].asserter"],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.conditions[0].asserter",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => ["$.conditions[0].report_origin", "$.conditions[0].asserter"],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.conditions[0].report_origin",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => ["$.conditions[0].report_origin", "$.conditions[0].asserter"],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.devices[0]",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "At least one of the parameters must be present",
                  "params" => ["$.devices[0].report_origin", "$.devices[0].asserter"],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.diagnostic_reports[0].performer.reference",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => ["$.diagnostic_reports[0].performer.reference", "$.diagnostic_reports[0].performer.text"],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.diagnostic_reports[0].performer.text",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => ["$.diagnostic_reports[0].performer.reference", "$.diagnostic_reports[0].performer.text"],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.diagnostic_reports[0].results_interpreter.reference",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => [
                    "$.diagnostic_reports[0].results_interpreter.reference",
                    "$.diagnostic_reports[0].results_interpreter.text"
                  ],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.diagnostic_reports[0].results_interpreter.text",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => [
                    "$.diagnostic_reports[0].results_interpreter.reference",
                    "$.diagnostic_reports[0].results_interpreter.text"
                  ],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.immunizations[1]",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "At least one of the parameters must be present",
                  "params" => ["$.immunizations[1].report_origin", "$.immunizations[1].performer"],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.immunizations[1].explanation.reasons",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => [
                    "$.immunizations[1].explanation.reasons",
                    "$.immunizations[1].explanation.reasons_not_given"
                  ],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.immunizations[1].explanation.reasons_not_given",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => [
                    "$.immunizations[1].explanation.reasons",
                    "$.immunizations[1].explanation.reasons_not_given"
                  ],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.medication_statements[0].asserter",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => ["$.medication_statements[0].report_origin", "$.medication_statements[0].asserter"],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.medication_statements[0].report_origin",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => ["$.medication_statements[0].report_origin", "$.medication_statements[0].asserter"],
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
                  "params" => ["$.observations[0].report_origin", "$.observations[0].performer"],
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
            },
            %{
              "entry" => "$.risk_assessments[0].predictions[0].when_period",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => [
                    "$.risk_assessments[0].predictions[0].when_range",
                    "$.risk_assessments[0].predictions[0].when_period"
                  ],
                  "rule" => "oneOf"
                }
              ]
            },
            %{
              "entry" => "$.risk_assessments[0].predictions[0].when_range",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Only one of the parameters must be present",
                  "params" => [
                    "$.risk_assessments[0].predictions[0].when_range",
                    "$.risk_assessments[0].predictions[0].when_period"
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
               Consumer.consume(%PackageCreateJob{
                 _id: to_string(job._id),
                 visit: %{
                   "id" => visit_id,
                   "period" => %{
                     "start" => start_datetime,
                     "end" => end_datetime
                   }
                 },
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end

    test "fail on invalid incoming_referral's used_by_legal_entity" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      expect_doctor(client_id, 2)

      encounter_id = UUID.uuid4()
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

      patient =
        insert(:patient, _id: patient_id_hash, episodes: %{UUID.binary_to_string!(episode.id.binary) => episode})

      condition_id = UUID.uuid4()
      insert(:condition, patient_id: patient_id_hash, _id: Mongo.string_to_uuid(condition_id))

      job = insert(:job)

      user_id = UUID.uuid4()
      expect_signature(@drfo)
      expect_employee_users(@drfo, user_id)

      visit_id = UUID.uuid4()
      episode_id = patient.episodes |> Map.keys() |> hd()
      employee_id = UUID.uuid4()

      start_datetime =
        DateTime.utc_now()
        |> DateTime.to_unix()
        |> Kernel.-(100_000)
        |> DateTime.from_unix!()
        |> DateTime.to_iso8601()

      end_datetime = DateTime.to_iso8601(DateTime.utc_now())

      service_request =
        insert(:service_request, used_by_employee: build(:reference), used_by_legal_entity: build(:reference))

      signed_content = %{
        "encounter" => %{
          "id" => encounter_id,
          "status" => "finished",
          "date" => DateTime.to_iso8601(DateTime.utc_now()),
          "visit" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "visit", "system" => "eHealth/resources"}]},
              "value" => visit_id
            }
          },
          "episode" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          "class" => %{"code" => "AMB", "system" => "eHealth/encounter_classes"},
          "type" => %{"coding" => [%{"code" => "AMB", "system" => "eHealth/encounter_types"}]},
          "reasons" => [
            %{"coding" => [%{"code" => "reason", "system" => "eHealth/ICPC2/reasons"}]}
          ],
          "diagnoses" => [
            %{
              "condition" => %{
                "identifier" => %{
                  "type" => %{"coding" => [%{"code" => "condition", "system" => "eHealth/resources"}]},
                  "value" => condition_id
                }
              },
              "role" => %{"coding" => [%{"code" => "primary", "system" => "eHealth/diagnosis_roles"}]}
            }
          ],
          "actions" => [%{"coding" => [%{"code" => "action", "system" => "eHealth/ICPC2/actions"}]}],
          "performer" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
              "value" => employee_id
            }
          },
          "prescriptions" => "Дієта №1",
          "incoming_referrals" => [
            %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                "value" => to_string(service_request._id)
              }
            }
          ]
        }
      }

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.encounter.incoming_referrals.[0].identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Service request is used by another legal_entity",
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
               Consumer.consume(%PackageCreateJob{
                 _id: to_string(job._id),
                 visit: %{
                   "id" => visit_id,
                   "period" => %{
                     "start" => start_datetime,
                     "end" => end_datetime
                   }
                 },
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end

    test "fail on invalid incoming_referral's category" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      expect_doctor(client_id, 2)

      encounter_id = UUID.uuid4()
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

      patient =
        insert(:patient, _id: patient_id_hash, episodes: %{UUID.binary_to_string!(episode.id.binary) => episode})

      condition_id = UUID.uuid4()
      insert(:condition, patient_id: patient_id_hash, _id: Mongo.string_to_uuid(condition_id))

      job = insert(:job)

      user_id = UUID.uuid4()
      expect_signature(@drfo)
      expect_employee_users(@drfo, user_id)

      visit_id = UUID.uuid4()
      episode_id = patient.episodes |> Map.keys() |> hd()
      employee_id = UUID.uuid4()

      start_datetime =
        DateTime.utc_now()
        |> DateTime.to_unix()
        |> Kernel.-(100_000)
        |> DateTime.from_unix!()
        |> DateTime.to_iso8601()

      end_datetime = DateTime.to_iso8601(DateTime.utc_now())

      service_request =
        insert(:service_request,
          used_by_employee: build(:reference),
          used_by_legal_entity:
            build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(client_id))),
          category:
            codeable_concept_coding(system: "eHealth/SNOMED/service_request_categories", code: "laboratory_procedure")
        )

      signed_content = %{
        "encounter" => %{
          "id" => encounter_id,
          "status" => "finished",
          "date" => DateTime.to_iso8601(DateTime.utc_now()),
          "visit" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "visit", "system" => "eHealth/resources"}]},
              "value" => visit_id
            }
          },
          "episode" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          },
          "class" => %{"code" => "AMB", "system" => "eHealth/encounter_classes"},
          "type" => %{"coding" => [%{"code" => "AMB", "system" => "eHealth/encounter_types"}]},
          "reasons" => [
            %{"coding" => [%{"code" => "reason", "system" => "eHealth/ICPC2/reasons"}]}
          ],
          "diagnoses" => [
            %{
              "condition" => %{
                "identifier" => %{
                  "type" => %{"coding" => [%{"code" => "condition", "system" => "eHealth/resources"}]},
                  "value" => condition_id
                }
              },
              "role" => %{"coding" => [%{"code" => "primary", "system" => "eHealth/diagnosis_roles"}]}
            }
          ],
          "actions" => [%{"coding" => [%{"code" => "action", "system" => "eHealth/ICPC2/actions"}]}],
          "performer" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
              "value" => employee_id
            }
          },
          "prescriptions" => "Дієта №1",
          "incoming_referrals" => [
            %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "service_request", "system" => "eHealth/resources"}]},
                "value" => to_string(service_request._id)
              }
            }
          ]
        }
      }

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.encounter.incoming_referrals.[0].identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Incorect service request type",
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
               Consumer.consume(%PackageCreateJob{
                 _id: to_string(job._id),
                 visit: %{
                   "id" => visit_id,
                   "period" => %{
                     "start" => start_datetime,
                     "end" => end_datetime
                   }
                 },
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })
    end
  end
end
