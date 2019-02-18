defmodule Core.Kafka.Consumer.CancelPackageTest do
  @moduledoc false

  use Core.ModelCase

  import Mox
  import Core.Expectations.DigitalSignatureExpectation
  import Core.Expectations.IlExpectations
  import Core.TestViews.CancelEncounterPackageView

  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.PackageCancelJob
  alias Core.Kafka.Consumer
  alias Core.Patients

  @status_pending Job.status(:pending)
  @entered_in_error "entered_in_error"

  @explanatory_letter "Я, Шевченко Наталія Олександрівна, здійснила механічну помилку"

  setup :verify_on_exit!

  describe "consume cancel package event" do
    setup do
      episode = build(:episode)

      encounter =
        build(
          :encounter,
          explanatory_letter: @explanatory_letter,
          episode:
            build(
              :reference,
              identifier: build(:identifier, value: episode.id, type: codeable_concept_coding(code: "episode"))
            )
        )

      context =
        build(
          :reference,
          identifier: build(:identifier, value: encounter.id, type: codeable_concept_coding(code: "encounter"))
        )

      %{test_data: {episode, encounter, context}}
    end

    test "success", %{test_data: {episode, encounter, context}} do
      expect(MediaStorageMock, :save, fn _, _, _, _ -> :ok end)
      expect(KafkaMock, :publish_mongo_event, 3, fn _event -> :ok end)

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

      client_id = UUID.uuid4()
      managing_organization = episode.managing_organization
      identifier = managing_organization.identifier

      episode = %{
        episode
        | managing_organization: %{
            managing_organization
            | identifier: %{identifier | value: Mongo.string_to_uuid(client_id)}
          }
      }

      user_id = prepare_signature_expectations()

      job = insert(:job)
      encounter_id = UUID.binary_to_string!(encounter.id.binary)
      immunization = build(:immunization, context: context)
      immunization_id = UUID.binary_to_string!(immunization.id.binary)

      allergy_intolerance = build(:allergy_intolerance, context: context)
      allergy_intolerance_id = UUID.binary_to_string!(allergy_intolerance.id.binary)
      allergy_intolerance2 = build(:allergy_intolerance, context: context)
      allergy_intolerance2_id = UUID.binary_to_string!(allergy_intolerance2.id.binary)

      risk_assessment = build(:risk_assessment, context: context)
      risk_assessment_id = UUID.binary_to_string!(risk_assessment.id.binary)

      device = build(:device, context: context)
      device_id = UUID.binary_to_string!(device.id.binary)

      medication_statement = build(:medication_statement, context: context)
      medication_statement_id = UUID.binary_to_string!(medication_statement.id.binary)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        encounters: %{encounter_id => encounter},
        immunizations: %{immunization_id => immunization},
        allergy_intolerances: %{
          allergy_intolerance_id => allergy_intolerance,
          allergy_intolerance2_id => allergy_intolerance2
        },
        risk_assessments: %{
          risk_assessment_id => risk_assessment
        },
        devices: %{
          device_id => device
        },
        medication_statements: %{
          medication_statement_id => medication_statement
        }
      )

      condition =
        insert(
          :condition,
          patient_id: patient_id_hash,
          context: context
        )

      observation = insert(:observation, patient_id: patient_id_hash, context: context)

      signed_data =
        %{
          "encounter" => render(:encounter, %{encounter | status: @entered_in_error}),
          "conditions" => render(:conditions, [%{condition | verification_status: @entered_in_error}]),
          "observations" => render(:observations, [%{observation | status: @entered_in_error}]),
          "immunizations" => render(:immunizations, [%{immunization | status: @entered_in_error}]),
          "allergy_intolerances" =>
            render(:allergy_intolerances, [%{allergy_intolerance | verification_status: @entered_in_error}]),
          "risk_assessments" => render(:risk_assessments, [%{risk_assessment | status: @entered_in_error}]),
          "devices" => render(:devices, [%{device | status: @entered_in_error}]),
          "medication_statements" =>
            render(:medication_statements, [%{medication_statement | status: @entered_in_error}])
        }
        |> Jason.encode!()
        |> Base.encode64()

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert [
                 %{"collection" => "patients", "operation" => "update_one", "set" => patient_set},
                 %{"collection" => "conditions", "operation" => "update_one", "filter" => condition_filter},
                 %{"collection" => "observations", "operation" => "update_one", "filter" => observation_filter},
                 %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
               ] = Jason.decode!(args)

        patient_set =
          patient_set
          |> Base.decode64!()
          |> BSON.decode()

        encounter_status = "encounters.#{encounter_id}.status"
        encounter_explanatory_letter = "encounters.#{encounter_id}.explanatory_letter"
        encounter_cancellation_reason = "encounters.#{encounter_id}.cancellation_reason"
        allergy_intolerance_status = "allergy_intolerances.#{allergy_intolerance_id}.verification_status"
        risk_assessment_status = "risk_assessments.#{risk_assessment_id}.status"
        immunization_status = "immunizations.#{immunization_id}.status"
        device_status = "devices.#{device_id}.status"
        medication_statements_status = "medication_statements.#{medication_statement_id}.status"

        assert %{
                 "$set" => %{
                   ^encounter_status => @entered_in_error,
                   ^encounter_explanatory_letter => @explanatory_letter,
                   ^encounter_cancellation_reason => %{
                     "coding" => [%{"system" => "eHealth/cancellation_reasons"}]
                   },
                   ^allergy_intolerance_status => @entered_in_error,
                   ^risk_assessment_status => @entered_in_error,
                   ^immunization_status => @entered_in_error,
                   ^device_status => @entered_in_error,
                   ^medication_statements_status => @entered_in_error
                 }
               } = patient_set

        assert %{"_id" => condition._id} == condition_filter |> Base.decode64!() |> BSON.decode()
        assert %{"_id" => observation._id} == observation_filter |> Base.decode64!() |> BSON.decode()
        assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

        set_bson = set |> Base.decode64!() |> BSON.decode()

        status = Job.status(:processed)

        assert %{
                 "$set" => %{
                   "status" => ^status,
                   "status_code" => 200,
                   "response" => %{}
                 }
               } = set_bson

        :ok
      end)

      assert :ok =
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: signed_data
               })
    end

    test "failed when no entities with entered_in_error status", %{test_data: {episode, encounter, context}} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      stub(IlMock, :get_legal_entity, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "ACTIVE",
             "public_name" => "LegalEntity 1"
           }
         }}
      end)

      client_id = UUID.uuid4()
      managing_organization = episode.managing_organization
      identifier = managing_organization.identifier

      episode = %{
        episode
        | managing_organization: %{
            managing_organization
            | identifier: %{identifier | value: Mongo.string_to_uuid(client_id)}
          }
      }

      user_id = prepare_signature_expectations()
      job = insert(:job)

      encounter_id = UUID.binary_to_string!(encounter.id.binary)
      immunization = build(:immunization, context: context)
      immunization_id = UUID.binary_to_string!(immunization.id.binary)

      allergy_intolerance = build(:allergy_intolerance, context: context)
      allergy_intolerance_id = UUID.binary_to_string!(allergy_intolerance.id.binary)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        encounters: %{encounter_id => encounter},
        immunizations: %{immunization_id => immunization},
        allergy_intolerances: %{allergy_intolerance_id => allergy_intolerance}
      )

      signed_data =
        %{
          "encounter" => render(:encounter, encounter),
          "immunizations" => render(:immunizations, [immunization]),
          "allergy_intolerances" => render(:allergy_intolerances, [allergy_intolerance])
        }
        |> Jason.encode!()
        |> Base.encode64()

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{"error" => ~s(At least one entity should have status "entered_in_error")},
        409
      )

      assert :ok =
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: signed_data
               })
    end

    test "faild when entity has alraady entered_in_error status", %{test_data: {episode, encounter, _}} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      stub(IlMock, :get_legal_entity, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "ACTIVE",
             "public_name" => "LegalEntity 1"
           }
         }}
      end)

      user_id = prepare_signature_expectations()
      client_id = UUID.uuid4()

      managing_organization = episode.managing_organization
      identifier = managing_organization.identifier

      episode = %{
        episode
        | managing_organization: %{
            managing_organization
            | identifier: %{identifier | value: Mongo.string_to_uuid(client_id)}
          }
      }

      job = insert(:job)
      encounter = %{encounter | status: @entered_in_error}
      encounter_id = UUID.binary_to_string!(encounter.id.binary)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        encounters: %{encounter_id => encounter}
      )

      signed_data =
        %{"encounter" => render(:encounter, encounter)}
        |> Jason.encode!()
        |> Base.encode64()

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{"error" => "Invalid transition for encounter - already entered_in_error"},
        409
      )

      assert :ok =
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: signed_data
               })
    end

    test "failed when episode managing organization invalid", %{test_data: {episode, encounter, context}} do
      expect(KafkaMock, :publish_mongo_event, 3, fn _event -> :ok end)

      stub(IlMock, :get_legal_entity, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "ACTIVE",
             "public_name" => "LegalEntity 1"
           }
         }}
      end)

      user_id = prepare_signature_expectations()

      job = insert(:job)
      encounter = %{encounter | status: @entered_in_error}

      encounter_id = UUID.binary_to_string!(encounter.id.binary)
      immunization = build(:immunization, context: context, status: @entered_in_error)
      immunization_id = UUID.binary_to_string!(immunization.id.binary)

      allergy_intolerance = build(:allergy_intolerance, context: context, verification_status: @entered_in_error)
      allergy_intolerance_id = UUID.binary_to_string!(allergy_intolerance.id.binary)
      allergy_intolerance2 = build(:allergy_intolerance, context: context)
      allergy_intolerance2_id = UUID.binary_to_string!(allergy_intolerance2.id.binary)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        encounters: %{encounter_id => encounter},
        immunizations: %{immunization_id => immunization},
        allergy_intolerances: %{
          allergy_intolerance_id => allergy_intolerance,
          allergy_intolerance2_id => allergy_intolerance2
        }
      )

      condition =
        insert(
          :condition,
          patient_id: patient_id_hash,
          context: context,
          verification_status: @entered_in_error
        )

      observation = insert(:observation, patient_id: patient_id_hash, context: context, status: @entered_in_error)

      signed_data =
        %{
          "encounter" => render(:encounter, encounter),
          "conditions" => render(:conditions, [condition]),
          "observations" => render(:observations, [observation]),
          "immunizations" => render(:immunizations, [immunization]),
          "allergy_intolerances" => render(:allergy_intolerances, [allergy_intolerance])
        }
        |> Jason.encode!()
        |> Base.encode64()

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.managing_organization.identifier.value",
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
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: UUID.uuid4(),
                 signed_data: signed_data
               })
    end

    test "fail on signed content", %{test_data: {episode, encounter, context}} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      user_id = prepare_signature_expectations()

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

      client_id = UUID.uuid4()
      managing_organization = episode.managing_organization
      identifier = managing_organization.identifier

      episode = %{
        episode
        | managing_organization: %{
            managing_organization
            | identifier: %{identifier | value: Mongo.string_to_uuid(client_id)}
          }
      }

      job = insert(:job)
      immunization = build(:immunization, context: context)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter},
        immunizations: %{UUID.binary_to_string!(immunization.id.binary) => immunization}
      )

      immunization_updated = %{immunization | lot_number: "100_000_000", status: @entered_in_error}

      signed_data =
        %{
          "encounter" => render(:encounter, encounter),
          "immunizations" => render(:immunizations, [immunization_updated])
        }
        |> Jason.encode!()
        |> Base.encode64()

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "error" =>
            "Submitted signed content does not correspond to previously created content: immunizations.0.lot_number"
        },
        409
      )

      assert :ok =
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: signed_data
               })
    end

    test "fail on validate diagnoses" do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      user_id = prepare_signature_expectations()

      stub(IlMock, :get_legal_entity, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "ACTIVE",
             "public_name" => "LegalEntity 1"
           }
         }}
      end)

      client_id = UUID.uuid4()

      episode =
        build(:episode, managing_organization: reference_coding(Mongo.string_to_uuid(client_id), code: "legal_entity"))

      job = insert(:job)
      condition_uuid = Mongo.string_to_uuid(UUID.uuid4())

      diagnosis =
        build(
          :diagnosis,
          condition:
            build(
              :reference,
              identifier: build(:identifier, value: condition_uuid, type: codeable_concept_coding(code: "condition"))
            )
        )

      encounter =
        build(
          :encounter,
          diagnoses: [diagnosis],
          episode:
            build(
              :reference,
              identifier: build(:identifier, value: episode.id, type: codeable_concept_coding(code: "episode"))
            )
        )

      context =
        build(
          :reference,
          identifier: build(:identifier, value: encounter.id, type: codeable_concept_coding(code: "encounter"))
        )

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter}
      )

      condition = insert(:condition, _id: condition_uuid, patient_id: patient_id_hash, context: context)

      signed_content =
        %{
          "encounter" => render(:encounter, encounter),
          "conditions" => render(:conditions, [%{condition | verification_status: @entered_in_error}])
        }
        |> Jason.encode!()
        |> Base.encode64()

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{"error" => "The condition can not be canceled while encounter is not canceled"},
        409
      )

      assert :ok =
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: signed_content
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end

    test "diagnosis deactivated" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      expect(MediaStorageMock, :save, fn _, _, _, _ -> :ok end)

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

      user_id = prepare_signature_expectations()
      client_id = UUID.uuid4()
      job = insert(:job)

      encounter_id = UUID.uuid4()
      encounter_uuid = Mongo.string_to_uuid(encounter_id)

      episode_id = UUID.uuid4()

      episode =
        build(
          :episode,
          id: Mongo.string_to_uuid(episode_id),
          managing_organization: reference_coding(Mongo.string_to_uuid(client_id), code: "legal_entity"),
          diagnoses_history: [
            build(:diagnoses_history, is_active: true),
            build(:diagnoses_history, is_active: true, evidence: reference_coding(encounter_uuid, [])),
            build(:diagnoses_history, is_active: false, evidence: reference_coding(encounter_uuid, []))
          ]
        )

      condition_uuid = Mongo.string_to_uuid(UUID.uuid4())

      encounter =
        build(
          :encounter,
          id: encounter_uuid,
          episode: reference_coding(episode.id, code: "episode"),
          diagnoses: build_list(1, :diagnosis, condition: reference_coding(condition_uuid, code: "condition"))
        )

      context = reference_coding(encounter.id, [])

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        encounters: %{encounter_id => encounter}
      )

      insert(:condition, _id: condition_uuid, patient_id: patient_id_hash, context: context)

      signed_data =
        %{"encounter" => render(:encounter, %{encounter | status: @entered_in_error})}
        |> Jason.encode!()
        |> Base.encode64()

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert [
                 %{"collection" => "patients", "operation" => "update_one", "set" => patient_set},
                 %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
               ] = Jason.decode!(args)

        patient_set =
          patient_set
          |> Base.decode64!()
          |> BSON.decode()

        diagnoses_active2 = "episodes.#{episode_id}.diagnoses_history.1.is_active"
        user_id = Mongo.string_to_uuid(user_id)

        assert %{
                 "$set" => %{
                   ^diagnoses_active2 => false,
                   "updated_by" => ^user_id
                 }
               } = patient_set

        assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

        set_bson = set |> Base.decode64!() |> BSON.decode()

        status = Job.status(:processed)

        assert %{
                 "$set" => %{
                   "status" => ^status,
                   "status_code" => 200,
                   "response" => %{}
                 }
               } = set_bson

        :ok
      end)

      assert :ok =
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: signed_data
               })
    end

    test "episode not found" do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      user_id = prepare_signature_expectations()

      job = insert(:job)
      encounter = build(:encounter)

      context =
        build(
          :reference,
          identifier: build(:identifier, value: encounter.id, type: codeable_concept_coding(code: "encounter"))
        )

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter}
      )

      condition =
        insert(
          :condition,
          patient_id: patient_id_hash,
          context: context,
          verification_status: @entered_in_error
        )

      signed_content =
        %{
          "encounter" => render(:encounter, encounter),
          "conditions" => render(:conditions, [condition])
        }
        |> Jason.encode!()
        |> Base.encode64()

      expect_job_update(
        job._id,
        Job.status(:failed),
        "Encounter's episode not found",
        404
      )

      assert :ok =
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: UUID.uuid4(),
                 signed_data: signed_content
               })
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
