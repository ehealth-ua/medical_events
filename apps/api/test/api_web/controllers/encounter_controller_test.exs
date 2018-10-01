defmodule Api.Web.EncounterControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase

  import Core.Expectations.CasherExpectation
  import Core.Expectations.DigitalSignatureExpectation
  import Mox

  alias Core.DateView
  alias Core.Mongo
  alias Core.Patient
  alias Core.Patients
  alias Core.ReferenceView
  alias Core.UUIDView

  @status_error "entered_in_error"

  describe "create visit" do
    test "patient not found", %{conn: conn} do
      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      conn = post(conn, encounter_path(conn, :create, UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      conn = post(conn, encounter_path(conn, :create, patient_id))
      assert json_response(conn, 409)
    end

    test "no signed data set", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      conn = post(conn, encounter_path(conn, :create, patient_id))
      assert response = json_response(conn, 422)

      assert [
               %{
                 "entry" => "$.signed_data",
                 "entry_type" => "json_data_property",
                 "rules" => [
                   %{
                     "description" => "required property signed_data was not present",
                     "params" => [],
                     "rule" => "required"
                   }
                 ]
               }
             ] = response["error"]["invalid"]
    end

    test "success create visit", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      now = DateTime.utc_now()

      conn =
        post(conn, encounter_path(conn, :create, patient_id), %{
          "visit" => %{
            "id" => UUID.uuid4(),
            "period" => %{"start" => DateTime.to_iso8601(now), "end" => DateTime.to_iso8601(now)}
          },
          "signed_data" => Base.encode64(Jason.encode!(%{}))
        })

      assert response = json_response(conn, 202)

      assert %{
               "data" => %{
                 "id" => _,
                 "inserted_at" => _,
                 "status" => "pending",
                 "updated_at" => _
               }
             } = response
    end
  end


  describe "show encounter" do
    test "successful show", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      encounter_in = build(:encounter)
      encounter_out = build(:encounter)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        encounters: %{
          UUID.binary_to_string!(encounter_in.id.binary) => encounter_in,
          UUID.binary_to_string!(encounter_out.id.binary) => encounter_out
        }
      )

      expect_get_person_data(patient_id)

      assert conn
             |> get(encounter_path(conn, :show, patient_id, UUID.binary_to_string!(encounter_in.id.binary)))
             |> json_response(200)
             |> Map.get("data")
             |> assert_json_schema("encounters/encounter_show.json")
    end

    test "invalid patient uuid", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      expect_get_person_data_empty()

      conn
      |> get(encounter_path(conn, :show, UUID.uuid4(), UUID.uuid4()))
      |> json_response(401)
    end

    test "invalid encounter uuid", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      encounter = build(:encounter)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter})
      expect_get_person_data(patient_id)

      conn
      |> get(encounter_path(conn, :show, patient_id, UUID.uuid4()))
      |> json_response(404)
    end

    test "get patient when no encounters", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, encounters: %{})
      expect_get_person_data(patient_id)

      conn
      |> get(encounter_path(conn, :show, patient_id, UUID.uuid4()))
      |> json_response(404)
    end
  end

  describe "index encounter" do
    test "successful search", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(encounter_path(conn, :index, patient_id))
        |> json_response(200)

      Enum.each(resp["data"], &assert_json_schema(&1, "encounters/encounter_show.json"))
      assert %{"page_number" => 1, "total_entries" => 2, "total_pages" => 1} = resp["paging"]
    end

    test "successful search with search parameters", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      episode = build(:reference)
      date_from = Date.utc_today() |> Date.add(-20) |> Date.to_iso8601()
      date_to = Date.utc_today() |> Date.add(-10) |> Date.to_iso8601()

      encounter_in = build(:encounter, date: Date.utc_today() |> Date.add(-15), episode: episode)
      encounter_out_1 = build(:encounter, date: Date.utc_today() |> Date.add(-15))
      encounter_out_2 = build(:encounter, date: Date.utc_today())

      encounters =
        [encounter_in, encounter_out_1, encounter_out_2]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = encounter ->
          {UUID.binary_to_string!(id), encounter}
        end)

      insert(:patient, _id: patient_id_hash, encounters: encounters)
      expect_get_person_data(patient_id)

      search_params = %{
        "episode_id" => episode.identifier.value,
        "date_from" => date_from,
        "date_to" => date_to
      }

      resp =
        conn
        |> get(encounter_path(conn, :index, patient_id), search_params)
        |> json_response(200)

      Enum.each(resp["data"], &assert_json_schema(&1, "encounters/encounter_show.json"))
      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      encounter = hd(resp["data"])
      assert encounter["id"] == UUID.binary_to_string!(encounter_in.id.binary)

      assert Date.compare(Date.from_iso8601!(date_from), Date.from_iso8601!(encounter["date"])) in [:lt, :eq]
      assert Date.compare(Date.from_iso8601!(date_to), Date.from_iso8601!(encounter["date"])) in [:gt, :eq]
      assert get_in(encounter, ~w(episode identifier value)) == UUID.binary_to_string!(episode.identifier.value.binary)
    end

    test "invalid patient uuid", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      expect_get_person_data_empty()

      conn
      |> get(encounter_path(conn, :index, UUID.uuid4()))
      |> json_response(401)
    end

    test "get patient when no encounters", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, encounters: %{})
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(encounter_path(conn, :index, patient_id))
        |> json_response(200)

      Enum.each(resp["data"], &assert_json_schema(&1, "encounters/encounter_show.json"))
      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end

    test "get patient when encounters list is null", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, encounters: nil)
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(encounter_path(conn, :index, patient_id))
        |> json_response(200)

      Enum.each(resp["data"], &assert_json_schema(&1, "encounters/encounter_show.json"))
      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end
  end

  describe "cancel encounter" do
    setup %{conn: conn} do
      expect_signature()

      expect(IlMock, :get_dictionaries, 2, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      episode = build(:episode)

      encounter =
        build(:encounter,
          episode:
            build(:reference,
              identifier: build(:identifier, value: episode.id, type: codeable_concept_coding(code: "episode"))
            )
        )

      context =
        build(:reference,
          identifier: build(:identifier, value: encounter.id, type: codeable_concept_coding(code: "encounter"))
        )

      {:ok, conn: put_consumer_id_header(conn), test_data: {episode, encounter, context}}
    end

    test "success", %{conn: conn, test_data: {episode, encounter, context}} do
      expect(KafkaMock, :publish_mongo_event, 3, fn _event -> :ok end)
      expect(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      immunization = build(:immunization, context: context, status: @status_error)
      allergy_intolerance = build(:allergy_intolerance, context: context)
      allergy_intolerance2 = build(:allergy_intolerance)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter},
        immunizations: %{UUID.binary_to_string!(immunization.id.binary) => immunization},
        allergy_intolerances: %{
          UUID.binary_to_string!(allergy_intolerance.id.binary) => allergy_intolerance,
          UUID.binary_to_string!(allergy_intolerance2.id.binary) => allergy_intolerance2
        }
      )

      condition =
        insert(:condition,
          patient_id: patient_id_hash,
          context: context,
          verification_status: @status_error
        )

      observation = insert(:observation, patient_id: patient_id_hash, context: context)

      expect_get_person_data(patient_id)
      expect_signature()

      request_data = %{
        "signed_data" =>
          %{
            "encounter" => render(:encounter, encounter),
            "conditions" => render(:conditions, [condition]),
            "observations" => render(:observations, [observation]),
            "immunizations" => render(:immunizations, [immunization]),
            "allergy_intolerances" => render(:allergy_intolerances, [allergy_intolerance])
          }
          |> Jason.encode!()
          |> Base.encode64()
      }

      assert conn
             |> patch(encounter_path(conn, :cancel, patient_id), request_data)
             |> json_response(202)
             |> get_in(["data", "status"])
             |> Kernel.==("pending")
    end


    test "fail on signed content", %{conn: conn, test_data: {episode, encounter, context}} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      expect(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      immunization = build(:immunization, context: context, status: @status_error)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter},
        immunizations: %{UUID.binary_to_string!(immunization.id.binary) => immunization}
      )

      expect_get_person_data(patient_id)

      immunization_updated = Map.put(immunization, :lot_number, "lot_number")

      request_data = %{
        "signed_data" =>
          %{
            "encounter" => render(:encounter, encounter),
            "immunizations" => render(:immunizations, [immunization_updated])
          }
          |> Jason.encode!()
          |> Base.encode64()
      }

      assert conn
             |> patch(encounter_path(conn, :cancel, patient_id), request_data)
             |> json_response(409)
             |> get_in(["error", "message"])
             |> Kernel.==("Submitted signed content does not correspond to previously created content")
    end

    test "fail on validate diagnoses", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      expect(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      episode = build(:episode)
      condition_uuid = Mongo.string_to_uuid(UUID.uuid4())

      diagnosis =
        build(:diagnosis,
          condition:
            build(:reference,
              identifier: build(:identifier, value: condition_uuid, type: codeable_concept_coding(code: "condition"))
            )
        )

      encounter =
        build(:encounter,
          diagnoses: [diagnosis],
          episode:
            build(:reference,
              identifier: build(:identifier, value: episode.id, type: codeable_concept_coding(code: "episode"))
            )
        )

      context =
        build(:reference,
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
        insert(:condition,
          _id: condition_uuid,
          patient_id: patient_id_hash,
          context: context,
          verification_status: @status_error
        )

      expect_get_person_data(patient_id)

      request_data = %{
        "signed_data" =>
          %{
            "encounter" => render(:encounter, encounter),
            "conditions" => render(:conditions, [condition])
          }
          |> Jason.encode!()
          |> Base.encode64()
      }

      assert conn
             |> patch(encounter_path(conn, :cancel, patient_id), request_data)
             |> json_response(409)
             |> get_in(["error", "message"])
             |> Kernel.==("The condition can not be canceled while encounter is not canceled")
    end
  end

  defp render(:encounter, encounter) do
    %{
      id: UUIDView.render(encounter.id),
      date: Date.to_string(encounter.date),
      explanatory_letter: encounter.explanatory_letter,
      cancellation_reason: ReferenceView.render(encounter.cancellation_reason),
      visit: encounter.visit |> ReferenceView.render() |> Map.delete(:display_value),
      episode: encounter.episode |> ReferenceView.render() |> Map.delete(:display_value),
      class: ReferenceView.render(encounter.class),
      type: ReferenceView.render(encounter.type),
      incoming_referrals:
        encounter.incoming_referrals |> ReferenceView.render() |> Enum.map(&Map.delete(&1, :display_value)),
      performer: ReferenceView.render(encounter.performer),
      reasons: ReferenceView.render(encounter.reasons),
      diagnoses: ReferenceView.render(encounter.diagnoses),
      actions: ReferenceView.render(encounter.actions),
      division: ReferenceView.render(encounter.division)
    }
  end

  defp render(:conditions, conditions) do
    condition_fields = ~w(
      clinical_status
      verification_status
      primary_source
    )a

    for condition <- conditions do
      condition_data = %{
        id: UUIDView.render(condition._id),
        body_sites: ReferenceView.render(condition.body_sites),
        severity: ReferenceView.render(condition.severity),
        stage: ReferenceView.render(condition.stage),
        code: ReferenceView.render(condition.code),
        context: ReferenceView.render(condition.context),
        evidences: ReferenceView.render(condition.evidences),
        asserted_date: DateView.render_date(condition.asserted_date),
        onset_date: DateView.render_date(condition.onset_date)
      }

      condition
      |> Map.take(condition_fields)
      |> Map.merge(condition_data)
      |> Map.merge(ReferenceView.render_source(condition.source))
    end
  end

  defp render(:observations, observations) do
    observation_fields = ~w(
      primary_source
      comment
      issued
    )a

    for observation <- observations do
      observation_data = %{
        id: UUIDView.render(observation._id),
        based_on: ReferenceView.render(observation.based_on),
        method: ReferenceView.render(observation.method),
        categories: ReferenceView.render(observation.categories),
        context: ReferenceView.render(observation.context),
        interpretation: ReferenceView.render(observation.interpretation),
        code: ReferenceView.render(observation.code),
        body_site: ReferenceView.render(observation.body_site),
        reference_ranges: ReferenceView.render(observation.reference_ranges),
        components: ReferenceView.render(observation.components)
      }

      observation
      |> Map.take(observation_fields)
      |> Map.merge(observation_data)
      |> Map.merge(ReferenceView.render_effective_at(observation.effective_at))
      |> Map.merge(ReferenceView.render_source(observation.source))
      |> Map.merge(ReferenceView.render_value(observation.value))
    end
  end

  defp render(:immunizations, immunizations) do
    immunization_fields = ~w(
      not_given
      primary_source
      manufacturer
      lot_number
    )a

    for immunization <- immunizations do
      immunization_data = %{
        id: UUIDView.render(immunization.id),
        vaccine_code: ReferenceView.render(immunization.vaccine_code),
        context: ReferenceView.render(immunization.context),
        date: DateView.render_date(immunization.date),
        legal_entity: immunization.legal_entity |> ReferenceView.render() |> Map.delete(:display_value),
        expiration_date: DateView.render_date(immunization.expiration_date),
        site: ReferenceView.render(immunization.site),
        route: ReferenceView.render(immunization.route),
        dose_quantity: ReferenceView.render(immunization.dose_quantity),
        reactions: ReferenceView.render(immunization.reactions),
        vaccination_protocols: ReferenceView.render(immunization.vaccination_protocols),
        explanation: ReferenceView.render(immunization.explanation)
      }

      immunization
      |> Map.take(immunization_fields)
      |> Map.merge(immunization_data)
      |> Map.merge(ReferenceView.render_source(immunization.source))
    end
  end

  defp render(:allergy_intolerances, allergy_intolerances) do
    allergy_intolerance_fields = ~w(
      verification_status
      clinical_status
      type
      category
      criticality
      primary_source
    )a

    for allergy_intolerance <- allergy_intolerances do
      allergy_intolerance_data = %{
        id: UUIDView.render(allergy_intolerance.id),
        context: ReferenceView.render(allergy_intolerance.context),
        code: ReferenceView.render(allergy_intolerance.code),
        asserted_date: DateView.render_datetime(allergy_intolerance.asserted_date),
        onset_date_time: DateView.render_datetime(allergy_intolerance.onset_date_time),
        last_occurrence: DateView.render_datetime(allergy_intolerance.last_occurrence)
      }

      allergy_intolerance
      |> Map.take(allergy_intolerance_fields)
      |> Map.merge(allergy_intolerance_data)
      |> Map.merge(ReferenceView.render_source(allergy_intolerance.source))
    end
  end
end
