defmodule Core.Kafka.Consumer.CreatePackageTest do
  @moduledoc false

  use Core.ModelCase

  import Core.Expectations.DigitalSignatureExpectation
  import Core.Expectations.IlExpectations
  import Mox

  alias Core.Immunization
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.PackageCreateJob
  alias Core.Kafka.Consumer
  alias Core.Mongo
  alias Core.Observation
  alias Core.Patients

  @status_pending Job.status(:pending)
  @status_valid Observation.status(:valid)

  describe "consume create package event" do
    test "empty content" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      job = insert(:job)
      user_id = prepare_signature_expectations()

      expect_job_update(
        job._id,
        %{
          invalid: [
            %{
              entry: "$",
              entry_type: "json_data_property",
              rules: [
                %{
                  description: "type mismatch. Expected Object but got String",
                  params: ["object"],
                  rule: :cast
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

      assert :ok =
               Consumer.consume(%PackageCreateJob{
                 _id: to_string(job._id),
                 visit: %{"id" => UUID.uuid4(), "period" => %{}},
                 signed_data: Base.encode64(""),
                 user_id: user_id,
                 client_id: UUID.uuid4()
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end

    test "empty map" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      job = insert(:job)
      user_id = prepare_signature_expectations()

      expect_job_update(
        job._id,
        %{
          invalid: [
            %{
              entry: "$.encounter",
              entry_type: "json_data_property",
              rules: [
                %{
                  description: "required property encounter was not present",
                  params: [],
                  rule: :required
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

      assert :ok =
               Consumer.consume(%PackageCreateJob{
                 _id: to_string(job._id),
                 visit: %{"id" => UUID.uuid4(), "period" => %{}},
                 signed_data: Base.encode64(Jason.encode!(%{})),
                 user_id: user_id,
                 client_id: UUID.uuid4()
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end

    test "visit not found" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      expect(MediaStorageMock, :save, fn _, _, _, _ -> :ok end)
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
      user_id = prepare_signature_expectations()
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
        %{
          invalid: [
            %{
              entry: "$.encounter.visit.identifier.value",
              entry_type: "json_data_property",
              rules: [
                %{
                  description: "Visit with such ID is not found",
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

      assert :ok =
               Consumer.consume(%PackageCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end

    test "success create package" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      expect(MediaStorageMock, :save, fn _, _, _, _ -> :ok end)
      client_id = UUID.uuid4()
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
      user_id = prepare_signature_expectations()
      visit_id = UUID.uuid4()
      episode_id = patient.episodes |> Map.keys() |> hd()
      observation_id = UUID.uuid4()
      observation_id2 = UUID.uuid4()
      employee_id = UUID.uuid4()
      service_request = insert(:service_request, used_by: build(:reference))

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
                "name" => "Vaccination Protocol Sequence 1",
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
                ],
                "dose_status" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/vaccination_dose_statuses",
                      "code" => "1"
                    }
                  ]
                },
                "dose_status_reason" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/vaccination_dose_statuse_reasons",
                      "code" => "coldchbrk"
                    }
                  ]
                }
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
            "id" => UUID.uuid4(),
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
            "reason_codeable_concept" => %{
              "coding" => [
                %{
                  "system" => "eHealth/risk_assessment_reasons",
                  "code" => "default_reason"
                }
              ]
            },
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
        ]
      }

      expect(KafkaMock, :publish_encounter_package_event, fn %{patient_save_data: %{"$set" => set_data}} ->
        assert observation_id ==
                 set_data["immunizations.#{immunization_id}.reactions"]
                 |> hd()
                 |> get_in(~w(detail identifier value)a)
                 |> to_string()

        assert observation_id2 ==
                 set_data["immunizations.#{db_immunization_id}.reactions"]
                 |> Enum.at(1)
                 |> get_in(~w(detail identifier value)a)
                 |> to_string()

        assert 2 == length(set_data["immunizations.#{db_immunization_id}.reactions"])
        assert set_data["immunizations.#{immunization_id}.reactions"]

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

      assert {:ok,
              %Core.Job{
                response_size: 2,
                status: @status_pending
              }} = Jobs.get_by_id(to_string(job._id))
    end

    test "failed when encounter reference episode doesnt match episode managing organization" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      expect(MediaStorageMock, :save, fn patient_id, _, _, resource_name ->
        {:ok, "http://localhost/#{patient_id}/#{resource_name}"}
      end)

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
      user_id = prepare_signature_expectations()
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
                "name" => "Vaccination Protocol Sequence 1",
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
                ],
                "dose_status" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/vaccination_dose_statuses",
                      "code" => "1"
                    }
                  ]
                },
                "dose_status_reason" => %{
                  "coding" => [
                    %{
                      "system" => "eHealth/vaccination_dose_statuse_reasons",
                      "code" => "coldchbrk"
                    }
                  ]
                }
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
        %{
          invalid: [
            %{
              entry: "$.encounter.episode.identifier.value",
              entry_type: "json_data_property",
              rules: [
                %{
                  description: "Managing_organization does not correspond to user's legal_entity",
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

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
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
      drfo = "1111111111"
      expect_signature(nil)
      expect_employee_users(drfo, user_id)

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

      expect_job_update(job._id, "Invalid drfo", 409)

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

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end
  end

  defp prepare_signature_expectations do
    user_id = UUID.uuid4()
    drfo = "1111111111"
    expect_signature(drfo)
    expect_employee_users(drfo, user_id)

    user_id
  end
end
