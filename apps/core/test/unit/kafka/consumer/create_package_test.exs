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
  @status_processed Job.status(:processed)
  @status_valid Observation.status(:valid)

  describe "consume create package event" do
    test "empty content" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      job = insert(:job)
      user_id = prepare_signature_expectations()

      assert :ok =
               Consumer.consume(%PackageCreateJob{
                 _id: to_string(job._id),
                 visit: %{"id" => UUID.uuid4(), "period" => %{}},
                 signed_data: Base.encode64(""),
                 user_id: user_id,
                 client_id: UUID.uuid4()
               })

      assert {:ok, %Job{status: @status_processed, response_size: 361}} = Jobs.get_by_id(to_string(job._id))
    end

    test "empty map" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      job = insert(:job)
      user_id = prepare_signature_expectations()

      assert :ok =
               Consumer.consume(%PackageCreateJob{
                 _id: to_string(job._id),
                 visit: %{"id" => UUID.uuid4(), "period" => %{}},
                 signed_data: Base.encode64(Jason.encode!(%{})),
                 user_id: user_id,
                 client_id: UUID.uuid4()
               })

      assert {:ok, %Job{status: @status_processed, response_size: 365}} = Jobs.get_by_id(to_string(job._id))
    end

    test "visit not found" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      expect(MediaStorageMock, :save, fn _, _, _, _ -> :ok end)
      client_id = UUID.uuid4()

      expect(IlMock, :get_employee, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "APPROVED",
             "employee_type" => "DOCTOR",
             "legal_entity" => %{"id" => client_id},
             "party" => %{
               "first_name" => "foo",
               "last_name" => "bar",
               "second_name" => "baz"
             }
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
          "date" => to_string(Date.utc_today()),
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
              "role" => %{"coding" => [%{"code" => "chief_complaint", "system" => "eHealth/diagnoses_roles"}]},
              "code" => %{"coding" => [%{"code" => "A10", "system" => "eHealth/ICD10/conditions"}]}
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

      assert :ok =
               Consumer.consume(%PackageCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })

      assert {:ok,
              %Core.Job{
                response_size: 375,
                status: @status_processed
              }} = Jobs.get_by_id(to_string(job._id))
    end

    test "success create package" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      expect(MediaStorageMock, :save, fn _, _, _, _ -> :ok end)
      client_id = UUID.uuid4()

      expect(IlMock, :get_employee, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "APPROVED",
             "employee_type" => "DOCTOR",
             "legal_entity" => %{"id" => client_id},
             "party" => %{
               "first_name" => "foo",
               "last_name" => "bar",
               "second_name" => "baz"
             }
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
      immunization = build(:immunization, id: Mongo.string_to_uuid(db_immunization_id))

      patient =
        insert(:patient,
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
          "date" => to_string(Date.utc_today()),
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
              "code" => %{"coding" => [%{"code" => "A10", "system" => "eHealth/ICD10/conditions"}]}
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
                "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                "value" => encounter_id
              }
            },
            "code" => %{"coding" => [%{"code" => "B10", "system" => "eHealth/ICPC2/conditions"}]},
            "clinical_status" => "test",
            "verification_status" => "test",
            "onset_date" => DateTime.to_iso8601(DateTime.utc_now()),
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
              %{"coding" => [%{"code" => "category", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{"coding" => [%{"code" => "code", "system" => "eHealth/observations_codes"}]},
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
              "coding" => [%{"code" => "category", "system" => "eHealth/observation_interpretations"}]
            },
            "body_site" => %{
              "coding" => [%{"code" => "category", "system" => "eHealth/body_sites"}]
            },
            "method" => %{
              "coding" => [%{"code" => "category", "system" => "eHealth/observation_methods"}]
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
                  "coding" => [%{"code" => "category", "system" => "eHealth/observations_codes"}]
                },
                "value_period" => %{
                  "start" => start_datetime,
                  "end" => end_datetime
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
            ],
            "reaction_on" => [
              %{
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
            ]
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
              %{"coding" => [%{"code" => "category", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{"coding" => [%{"code" => "code", "system" => "eHealth/observations_codes"}]},
            "effective_period" => %{
              "start" => start_datetime,
              "end" => end_datetime
            },
            "primary_source" => false,
            "report_origin" => %{
              "coding" => [%{"code" => "employee", "system" => "eHealth/report_origins"}]
            },
            "reaction_on" => [
              %{
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
              }
            ],
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
                "value" => employee_id
              }
            },
            "primary_source" => true,
            "date" => DateTime.to_iso8601(DateTime.utc_now()),
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
          },
          %{
            "id" => immunization_id2,
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
                "value" => employee_id
              }
            },
            "primary_source" => true,
            "date" => DateTime.to_iso8601(DateTime.utc_now()),
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
                  "system" => "eHealth/allergy_intolerances_codes",
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
            "last_occurence" => DateTime.to_iso8601(DateTime.utc_now()),
            "onset_date_time" => DateTime.to_iso8601(DateTime.utc_now())
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
                 |> hd()
                 |> get_in(~w(detail identifier value)a)
                 |> to_string()

        assert 2 == length(set_data["immunizations.#{db_immunization_id}.reactions"])

        assert nil == set_data["immunizations.#{immunization_id2}.reactions"]

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

      expect(IlMock, :get_employee, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "APPROVED",
             "employee_type" => "DOCTOR",
             "legal_entity" => %{"id" => client_id},
             "party" => %{
               "first_name" => "foo",
               "last_name" => "bar",
               "second_name" => "baz"
             }
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
          "date" => to_string(Date.utc_today()),
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
              "code" => %{"coding" => [%{"code" => "A10", "system" => "eHealth/ICD10/conditions"}]}
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
                "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                "value" => encounter_id
              }
            },
            "code" => %{"coding" => [%{"code" => "B10", "system" => "eHealth/ICPC2/conditions"}]},
            "clinical_status" => "test",
            "verification_status" => "test",
            "onset_date" => DateTime.to_iso8601(DateTime.utc_now()),
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
              %{"coding" => [%{"code" => "category", "system" => "eHealth/observation_categories"}]}
            ],
            "code" => %{"coding" => [%{"code" => "code", "system" => "eHealth/observations_codes"}]},
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
              "coding" => [%{"code" => "category", "system" => "eHealth/observation_interpretations"}]
            },
            "body_site" => %{
              "coding" => [%{"code" => "category", "system" => "eHealth/body_sites"}]
            },
            "method" => %{
              "coding" => [%{"code" => "category", "system" => "eHealth/observation_methods"}]
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
                  "coding" => [%{"code" => "category", "system" => "eHealth/observations_codes"}]
                },
                "value_period" => %{
                  "start" => start_datetime,
                  "end" => end_datetime
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
                "value" => employee_id
              }
            },
            "primary_source" => true,
            "date" => DateTime.to_iso8601(DateTime.utc_now()),
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
            "last_occurence" => DateTime.to_iso8601(DateTime.utc_now()),
            "onset_date_time" => DateTime.to_iso8601(DateTime.utc_now())
          }
        ]
      }

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
                response: %{
                  "invalid" => [
                    %{
                      "entry" => "$.encounter.episode.identifier.value",
                      "rules" => [
                        %{
                          "description" => "User is not allowed to change objects, created by another legal_entity",
                          "params" => [],
                          "rule" => "invalid"
                        }
                      ]
                    }
                  ]
                },
                status_code: 422
              }} = Jobs.get_by_id(to_string(job._id))
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
          "date" => to_string(Date.utc_today()),
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
              "code" => %{"coding" => [%{"code" => "A10", "system" => "eHealth/ICD10/conditions"}]}
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
                response: "Invalid drfo",
                status_code: 409
              }} = Jobs.get_by_id(to_string(job._id))
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
