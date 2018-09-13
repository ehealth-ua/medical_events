defmodule Core.Kafka.Consumer.CreatePackageTest do
  @moduledoc false

  use Core.ModelCase

  alias Core.Kafka.Consumer
  alias Core.Immunization
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.PackageCreateJob
  alias Core.Observation
  import Mox
  import Core.Expectations.DigitalSignature

  @status_processed Job.status(:processed)
  @status_valid Observation.status(:valid)

  describe "consume create package event" do
    test "empty content" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      job = insert(:job)
      signature()

      assert :ok =
               Consumer.consume(%PackageCreateJob{
                 _id: job._id,
                 visit: %{"id" => UUID.uuid4(), "period" => %{}},
                 signed_data: Base.encode64("")
               })

      assert {:ok, %Job{status: @status_processed, response_size: 361}} = Jobs.get_by_id(job._id)
    end

    test "empty map" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      job = insert(:job)
      signature()

      assert :ok =
               Consumer.consume(%PackageCreateJob{
                 _id: job._id,
                 visit: %{"id" => UUID.uuid4(), "period" => %{}},
                 signed_data: Base.encode64(Jason.encode!(%{}))
               })

      assert {:ok, %Job{status: @status_processed, response_size: 365}} = Jobs.get_by_id(job._id)
    end

    test "visit already exists" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      client_id = UUID.uuid4()

      expect(IlMock, :get_employee, 2, fn id, _ ->
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
      patient = insert(:patient)
      condition = insert(:condition, patient_id: patient._id)
      visit_id = patient.visits |> Map.keys() |> hd
      job = insert(:job)
      signature()
      episode_id = patient.episodes |> Map.keys() |> hd

      signed_content = %{
        "encounter" => %{
          "id" => encounter_id,
          "status" => "finished",
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
                  "value" => condition._id
                }
              },
              "role" => %{"coding" => [%{"code" => "chief_complaint", "system" => "eHealth/diagnoses_roles"}]},
              "code" => %{"coding" => [%{"code" => "code", "system" => "eHealth/ICD10/conditions"}]}
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
              "value" => UUID.uuid4()
            }
          }
        }
      }

      user_id = UUID.uuid4()

      assert :ok =
               Consumer.consume(%PackageCreateJob{
                 _id: job._id,
                 patient_id: patient._id,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })

      assert {:ok,
              %Core.Job{
                response_size: 375,
                status: @status_processed
              }} = Jobs.get_by_id(job._id)
    end

    # TODO: not completed
    test "success create package" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      client_id = UUID.uuid4()

      expect(IlMock, :get_employee, 3, fn id, _ ->
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
      patient = insert(:patient)
      db_observation = insert(:observation, patient_id: patient._id)
      condition_id = UUID.uuid4()
      job = insert(:job)
      signature()
      visit_id = UUID.uuid4()
      episode_id = patient.episodes |> Map.keys() |> hd
      observation_id = UUID.uuid4()

      signed_content = %{
        "encounter" => %{
          "id" => encounter_id,
          "status" => "finished",
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
              "role" => %{"coding" => [%{"code" => "chief_complaint", "system" => "eHealth/diagnoses_roles"}]},
              "code" => %{"coding" => [%{"code" => "code", "system" => "eHealth/ICD10/conditions"}]}
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
              "value" => UUID.uuid4()
            }
          }
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
            "code" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/ICPC2/conditions"}]},
            "clinical_status" => "test",
            "verification_status" => "test",
            "onset_date" => Date.to_iso8601(Date.utc_today()),
            "severity" => %{"coding" => [%{"code" => "55604002", "system" => "eHealth/severity"}]},
            "body_sites" => [%{"coding" => [%{"code" => "181414000", "system" => "eHealth/body_sites"}]}],
            "stage" => %{
              "summary" => %{"coding" => [%{"code" => "181414000", "system" => "eHealth/condition_stages"}]}
            },
            "evidences" => [
              %{
                "codes" => [%{"coding" => [%{"code" => "condition", "system" => "eHealth/ICD10/conditions"}]}],
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
                      "value" => db_observation._id
                    }
                  }
                ]
              }
            ]
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
              %{"coding" => [%{"code" => "category", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{"coding" => [%{"code" => "code", "system" => "eHealth/observations_codes"}]},
            "effective_period" => %{
              "start" => DateTime.to_iso8601(DateTime.utc_now()),
              "end" => DateTime.to_iso8601(DateTime.utc_now())
            },
            "primary_source" => true,
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => UUID.uuid4()
              }
            },
            "interpretation" => %{
              "coding" => [%{"code" => "category", "system" => "eHealth/observation_interpretations"}]
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
                  "coding" => [%{"code" => "category", "system" => "eHealth/observations_codes"}]
                },
                "value_period" => %{
                  "start" => DateTime.to_iso8601(DateTime.utc_now()),
                  "end" => DateTime.to_iso8601(DateTime.utc_now())
                },
                "interpretation" => %{
                  "coding" => [%{"code" => "category", "system" => "eHealth/observation_interpretations"}]
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
              %{"coding" => [%{"code" => "category", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{"coding" => [%{"code" => "code", "system" => "eHealth/observations_codes"}]},
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
            "status" => Immunization.status(:completed),
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
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => UUID.uuid4()
              }
            },
            "primary_source" => true,
            "date" => to_string(Date.utc_today()),
            "issued" => DateTime.to_iso8601(DateTime.utc_now()),
            "site" => %{"coding" => [%{"code" => "LA", "system" => "eHealth/body_sites"}]},
            "route" => %{"coding" => [%{"code" => "IM", "system" => "eHealth/vaccination_routes"}]},
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
                  "system" => "eHealth/allergy_intolerances_codes",
                  "code" => "227493005"
                }
              ]
            },
            "performer" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                "value" => UUID.uuid4()
              }
            },
            "primary_source" => true,
            "clinical_status" => "active",
            "verification_status" => "confirmed",
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
               Consumer.consume(%PackageCreateJob{
                 _id: job._id,
                 visit: %{
                   "id" => visit_id,
                   "period" => %{
                     "start" => DateTime.to_iso8601(DateTime.utc_now()),
                     "end" => DateTime.to_iso8601(DateTime.utc_now())
                   }
                 },
                 patient_id: patient._id,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })

      assert {:ok,
              %Core.Job{
                response_size: 831,
                status: @status_processed
              }} = Jobs.get_by_id(job._id)
    end
  end
end
