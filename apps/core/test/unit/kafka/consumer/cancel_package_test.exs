defmodule Core.Kafka.Consumer.CancelPackageTest do
  @moduledoc false

  use Core.ModelCase

  import Mox
  import Core.Expectations.DigitalSignatureExpectation
  import Core.Expectations.IlExpectations
  import Core.TestViews.CancelEncounterPackageView

  alias Core.AllergyIntolerance
  alias Core.Conditions
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.PackageCancelJob
  alias Core.Kafka.Consumer
  alias Core.Observations
  alias Core.Patients

  @job_status_processed Job.status(:processed)
  @job_status_pending Job.status(:pending)
  @entered_in_error "entered_in_error"

  @explanatory_letter "Я, Шевченко Наталія Олександрівна, здійснила механічну помилку"

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
      expect(KafkaMock, :publish_mongo_event, 5, fn _event -> :ok end)
      stub(KafkaMock, :publish_encounter_package_event, fn _event -> :ok end)

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
      expect_doctor(client_id)
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

      condition_id = UUID.binary_to_string!(condition._id.binary)

      observation = insert(:observation, patient_id: patient_id_hash, context: context, status: @entered_in_error)
      observation_id = UUID.binary_to_string!(observation._id.binary)

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

      assert :ok =
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: signed_data
               })

      assert {:ok,
              %Core.Job{
                response_size: _,
                response: "",
                status: @job_status_pending,
                status_code: 200
              }} = Jobs.get_by_id(to_string(job._id))

      patient = Patients.get_by_id(patient_id_hash)
      encounter = patient["encounters"][encounter_id]

      assert @entered_in_error == encounter["status"]
      assert @explanatory_letter == encounter["explanatory_letter"]
      assert "eHealth/cancellation_reasons" == encounter["cancellation_reason"]["coding"] |> hd() |> Map.get("system")

      assert @entered_in_error == patient["allergy_intolerances"][allergy_intolerance_id]["verification_status"]
      assert @entered_in_error == patient["immunizations"][immunization_id]["status"]

      assert AllergyIntolerance.verification_status(:confirmed) ==
               patient["allergy_intolerances"][allergy_intolerance2_id]["verification_status"]

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

    test "faild when episode managing organization invalid", %{test_data: {episode, encounter, context}} do
      expect(KafkaMock, :publish_mongo_event, 5, fn _event -> :ok end)

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

      assert :ok =
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: UUID.uuid4(),
                 signed_data: signed_data
               })

      assert {:ok,
              %Core.Job{
                response_size: _,
                response: %{
                  "invalid" => [
                    %{
                      "entry" => "$.managing_organization.identifier.value",
                      "entry_type" => "json_data_property",
                      "rules" => [
                        %{
                          "description" => "User can create an episode only for the legal entity for which he works",
                          "params" => [],
                          "rule" => "invalid"
                        }
                      ]
                    }
                  ]
                },
                status: @job_status_processed,
                status_code: 422
              }} = Jobs.get_by_id(to_string(job._id))
    end

    test "fail on signed content", %{test_data: {episode, encounter, context}} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
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
      expect_doctor(client_id)
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
      immunization = build(:immunization, context: context, status: @entered_in_error)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter},
        immunizations: %{UUID.binary_to_string!(immunization.id.binary) => immunization}
      )

      immunization_updated = Map.put(immunization, :lot_number, "100_000_000")

      signed_data =
        %{
          "encounter" => render(:encounter, encounter),
          "immunizations" => render(:immunizations, [immunization_updated])
        }
        |> Jason.encode!()
        |> Base.encode64()

      assert :ok =
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: signed_data
               })

      assert {:ok,
              %Core.Job{
                response_size: _,
                response: %{"error" => error},
                status: @job_status_processed
              }} = Jobs.get_by_id(to_string(job._id))

      assert String.contains?(error, "Submitted signed content does not correspond to previously created content")
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
      expect_doctor(client_id)

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

      condition =
        insert(
          :condition,
          _id: condition_uuid,
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

      assert :ok =
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: signed_content
               })

      assert {:ok,
              %Core.Job{
                response_size: _,
                response: %{"error" => error},
                status: @job_status_processed
              }} = Jobs.get_by_id(to_string(job._id))

      assert "The condition can not be canceled while encounter is not canceled" == error
    end

    test "diagnosis deactivated" do
      expect(MediaStorageMock, :save, fn _, _, _, _ -> :ok end)
      stub(KafkaMock, :publish_encounter_package_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
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
      expect_doctor(client_id)

      job = insert(:job)

      encounter_id = UUID.uuid4()
      encounter_uuid = Mongo.string_to_uuid(encounter_id)

      episode =
        build(
          :episode,
          managing_organization: reference_coding(Mongo.string_to_uuid(client_id), code: "legal_entity"),
          diagnoses_history:
            build_list(1, :diagnoses_history, is_active: true, evidence: reference_coding(encounter_uuid, []))
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
        %{"encounter" => render(:encounter, encounter)}
        |> Jason.encode!()
        |> Base.encode64()

      assert :ok =
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: signed_data
               })

      assert {:ok,
              %Core.Job{
                response_size: _,
                status: @job_status_pending
              }} = Jobs.get_by_id(to_string(job._id))
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

      assert :ok =
               Consumer.consume(%PackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: UUID.uuid4(),
                 signed_data: signed_content
               })

      assert {:ok,
              %Core.Job{
                response_size: _,
                response: "Encounter's episode not found",
                status_code: 404,
                status: @job_status_processed
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
