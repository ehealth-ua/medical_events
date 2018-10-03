defmodule Core.Kafka.Consumer.CancelPackageTest do
  @moduledoc false

  use Core.ModelCase

  import Mox
  import Core.Expectations.DigitalSignatureExpectation

  alias Core.Conditions
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.PackageCancelJob
  alias Core.Kafka.Consumer
  alias Core.Observation
  alias Core.Observations
  alias Core.Patients

  @status_processed Job.status(:processed)
  @entered_in_error "entered_in_error"

  describe "consume cancel package event" do
    test "success" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      client_id = UUID.uuid4()

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      expect(IlMock, :get_employee, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "APPROVED",
             "employee_type" => "DOCTOR",
             "legal_entity" => %{"id" => client_id}
           }
         }}
      end)

      encounter_uuid = Mongo.string_to_uuid(UUID.uuid4())

      episode =
        build(:episode,
          diagnoses_history: build_list(1, :diagnoses_history, evidence: reference_value(encounter_uuid))
        )

      encounter = build(:encounter, id: encounter_uuid, episode: reference_value(episode.id))
      context = reference_value(encounter.id)

      allergy_intolerance = build(:allergy_intolerance, context: context)
      allergy_intolerance_id = UUID.binary_to_string!(allergy_intolerance.id.binary)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient =
        insert(:patient,
          _id: patient_id_hash,
          episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
          encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter},
          allergy_intolerances: %{
            allergy_intolerance_id => allergy_intolerance
          }
        )

      condition = insert(:condition, patient_id: patient_id_hash, context: context)
      observation = insert(:observation, patient_id: patient_id_hash, context: context)

      encounter_id = UUID.binary_to_string!(encounter.id.binary)
      observation_id = UUID.binary_to_string!(observation._id.binary)
      condition_id = UUID.binary_to_string!(condition._id.binary)

      job = insert(:job)
      expect_signature()
      visit_id = UUID.uuid4()
      episode_id = patient.episodes |> Map.keys() |> hd()
      employee_id = UUID.uuid4()

      explanatory_letter = "Я, Шевченко Наталія Олександрівна, здійснила механічну помилку"

      signed_content = %{
        "encounter" => %{
          "id" => encounter_id,
          "status" => @entered_in_error,
          "date" => to_string(Date.utc_today()),
          "explanatory_letter" => explanatory_letter,
          "cancellation_reason" => %{
            "coding" => [%{"code" => "misspelling", "system" => "eHealth/cancellation_reasons"}],
            "text" => "some text"
          },
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
                  "type" => %{
                    "coding" => [%{"code" => "condition", "system" => "eHealth/resources"}]
                  },
                  "value" => condition_id
                }
              },
              "role" => %{
                "coding" => [
                  %{"code" => "chief_complaint", "system" => "eHealth/diagnoses_roles"}
                ]
              },
              "code" => %{
                "coding" => [%{"code" => "code", "system" => "eHealth/ICD10/conditions"}]
              }
            }
          ],
          "actions" => [%{"coding" => [%{"code" => "action", "system" => "eHealth/actions"}]}],
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
          }
        },
        "conditions" => [
          %{
            "id" => condition_id,
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]
                },
                "value" => encounter_id
              }
            },
            "code" => %{
              "coding" => [%{"code" => "legal_entity", "system" => "eHealth/ICPC2/conditions"}]
            },
            "clinical_status" => "test",
            "verification_status" => @entered_in_error,
            "onset_date" => Date.to_iso8601(Date.utc_today()),
            "severity" => %{"coding" => [%{"code" => "55604002", "system" => "eHealth/severity"}]},
            "body_sites" => [
              %{"coding" => [%{"code" => "181414000", "system" => "eHealth/body_sites"}]}
            ],
            "stage" => %{
              "summary" => %{
                "coding" => [%{"code" => "181414000", "system" => "eHealth/condition_stages"}]
              }
            },
            "evidences" => [
              %{
                "codes" => [
                  %{
                    "coding" => [%{"code" => "condition", "system" => "eHealth/ICD10/conditions"}]
                  }
                ],
                "details" => [
                  %{
                    "identifier" => %{
                      "type" => %{
                        "coding" => [%{"code" => "observation", "system" => "eHealth/resources"}]
                      },
                      "value" => observation_id
                    }
                  },
                  %{
                    "identifier" => %{
                      "type" => %{
                        "coding" => [%{"code" => "observation", "system" => "eHealth/resources"}]
                      },
                      "value" => observation_id
                    }
                  }
                ]
              }
            ],
            "primary_source" => true,
            "asserter" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]
                },
                "value" => employee_id
              }
            }
          }
        ],
        "observations" => [
          %{
            "id" => observation_id,
            "status" => @entered_in_error,
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]
                },
                "value" => encounter_id
              }
            },
            "categories" => [
              %{
                "coding" => [
                  %{"code" => "category", "system" => "eHealth/observation_categories"}
                ]
              }
            ],
            "code" => %{
              "coding" => [%{"code" => "code", "system" => "eHealth/observations_codes"}]
            },
            "effective_period" => %{
              "start" => DateTime.to_iso8601(DateTime.utc_now()),
              "end" => DateTime.to_iso8601(DateTime.utc_now())
            },
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]
                },
                "value" => employee_id
              }
            },
            "interpretation" => %{
              "coding" => [
                %{"code" => "category", "system" => "eHealth/observation_interpretations"}
              ]
            },
            "body_site" => %{
              "coding" => [%{"code" => "category", "system" => "eHealth/body_sites"}]
            },
            "method" => %{
              "coding" => [%{"code" => "category", "system" => "eHealth/observation_methods"}]
            },
            "value_period" => %{
              "start" => DateTime.to_iso8601(DateTime.utc_now()),
              "end" => DateTime.to_iso8601(DateTime.utc_now())
            },
            "reference_ranges" => [
              %{
                "type" => %{
                  "coding" => [
                    %{"code" => "category", "system" => "eHealth/reference_range_types"}
                  ]
                },
                "applies_to" => [
                  %{
                    "coding" => [
                      %{"code" => "category", "system" => "eHealth/reference_range_applications"}
                    ]
                  }
                ]
              }
            ],
            "components" => [
              %{
                "code" => %{
                  "coding" => [%{"code" => "category", "system" => "eHealth/observations_codes"}]
                },
                "value_period" => %{
                  "start" => DateTime.to_iso8601(DateTime.utc_now()),
                  "end" => DateTime.to_iso8601(DateTime.utc_now())
                },
                "interpretation" => %{
                  "coding" => [
                    %{"code" => "category", "system" => "eHealth/observation_interpretations"}
                  ]
                },
                "reference_ranges" => [
                  %{
                    "applies_to" => [
                      %{
                        "coding" => [
                          %{
                            "code" => "category",
                            "system" => "eHealth/reference_range_applications"
                          }
                        ]
                      }
                    ]
                  }
                ]
              }
            ]
          },
          %{
            "id" => UUID.uuid4(),
            "status" => Observation.status(:valid),
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "context" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]
                },
                "value" => encounter_id
              }
            },
            "categories" => [
              %{
                "coding" => [
                  %{"code" => "category", "system" => "eHealth/observation_categories"}
                ]
              }
            ],
            "code" => %{
              "coding" => [%{"code" => "code", "system" => "eHealth/observations_codes"}]
            },
            "effective_period" => %{
              "start" => DateTime.to_iso8601(DateTime.utc_now()),
              "end" => DateTime.to_iso8601(DateTime.utc_now())
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
            "not_given" => false,
            "vaccine_code" => %{
              "coding" => [
                %{
                  "system" => "eHealth/vaccines_codes",
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
                "type" => %{
                  "coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]
                },
                "value" => employee_id
              }
            },
            "primary_source" => true,
            "date" => to_string(Date.utc_today()),
            "site" => %{"coding" => [%{"code" => "LA", "system" => "eHealth/body_sites"}]},
            "route" => %{
              "coding" => [%{"code" => "IM", "system" => "eHealth/vaccination_routes"}]
            },
            "dose_quantity" => %{
              "value" => 18,
              "unit" => "mg",
              "system" => "eHealth/dose_quantities"
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
            "reactions" => [
              %{
                "date" => Date.utc_today(),
                "detail" => %{
                  "identifier" => %{
                    "type" => %{
                      "coding" => [
                        %{
                          "system" => "eHealth/resources",
                          "code" => "observation"
                        }
                      ]
                    },
                    "value" => observation_id
                  }
                },
                "reported" => true
              }
            ],
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
                      "code" => "count"
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
                  "system" => "eHealth/allergy_intolerances_codes",
                  "code" => "227493005"
                }
              ]
            },
            "asserter" => %{
              "identifier" => %{
                "type" => %{
                  "coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]
                },
                "value" => employee_id
              }
            },
            "primary_source" => true,
            "clinical_status" => "active",
            "verification_status" => @entered_in_error,
            "type" => "allergy",
            "category" => "food",
            "criticality" => "low",
            "asserted_date" => DateTime.to_iso8601(DateTime.utc_now()),
            "last_occurence" => DateTime.to_iso8601(DateTime.utc_now()),
            "onset_date_time" => DateTime.to_iso8601(DateTime.utc_now())
          }
        ]
      }

      user_id = UUID.uuid4()

      assert :ok =
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: signed_content |> Jason.encode!() |> Base.encode64()
               })

      assert {:ok,
              %Core.Job{
                response_size: _,
                status: @status_processed
              }} = Jobs.get_by_id(to_string(job._id))

      patient = Patients.get_by_id(patient_id_hash)

      assert @entered_in_error == patient["allergy_intolerances"][allergy_intolerance_id]["verification_status"]

      encounter = patient["encounters"][encounter_id]

      assert @entered_in_error == encounter["status"]
      assert explanatory_letter == encounter["explanatory_letter"]
      assert encounter["cancellation_reason"] != nil

      assert @entered_in_error ==
               patient_id_hash
               |> Conditions.get(condition_id)
               |> elem(1)
               |> Map.get(:verification_status)

      assert @entered_in_error ==
               patient_id_hash
               |> Observations.get(observation_id)
               |> elem(1)
               |> Map.get(:status)
    end

    test "diagnosis deactivated" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      client_id = UUID.uuid4()

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      expect_signature()

      encounter_uuid = Mongo.string_to_uuid(UUID.uuid4())

      episode =
        build(:episode,
          diagnoses_history:
            build_list(1, :diagnoses_history, is_active: true, evidence: reference_value(encounter_uuid))
        )

      encounter = build(:encounter, id: encounter_uuid, episode: reference_value(episode.id))
      encounter_id = UUID.binary_to_string!(encounter.id.binary)
      context = reference_value(encounter.id)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient =
        insert(:patient,
          _id: patient_id_hash,
          episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
          encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter}
        )

      condition = insert(:condition, patient_id: patient_id_hash, context: context)
      condition_id = UUID.binary_to_string!(condition._id.binary)

      job = insert(:job)

      visit_id = UUID.uuid4()
      episode_id = patient.episodes |> Map.keys() |> hd()
      employee_id = UUID.uuid4()

      signed_content = %{
        "encounter" => %{
          "id" => encounter_id,
          "date" => to_string(Date.utc_today()),
          "explanatory_letter" => "Я, Шевченко Наталія Олександрівна, здійснила механічну помилку",
          "cancellation_reason" => %{
            "coding" => [%{"code" => "misspelling", "system" => "eHealth/cancellation_reasons"}],
            "text" => "some text"
          },
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
                  "type" => %{
                    "coding" => [%{"code" => "condition", "system" => "eHealth/resources"}]
                  },
                  "value" => condition_id
                }
              },
              "role" => %{
                "coding" => [
                  %{"code" => "chief_complaint", "system" => "eHealth/diagnoses_roles"}
                ]
              },
              "code" => %{
                "coding" => [%{"code" => "code", "system" => "eHealth/ICD10/conditions"}]
              }
            }
          ],
          "actions" => [%{"coding" => [%{"code" => "action", "system" => "eHealth/actions"}]}],
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
          }
        }
      }

      assert :ok =
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: UUID.uuid4(),
                 client_id: client_id,
                 signed_data: signed_content |> Jason.encode!() |> Base.encode64()
               })

      assert {:ok,
              %Core.Job{
                response_size: _,
                status: @status_processed
              }} = Jobs.get_by_id(to_string(job._id))

      patient = Patients.get_by_id(patient_id_hash)

      assert [%{"is_active" => false} | _] = patient["episodes"][episode_id]["diagnoses_history"]
    end
  end
end
