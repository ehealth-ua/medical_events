defmodule Api.Web.DiagnosticReportControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase

  import Core.Expectations.CasherExpectation
  import Mox

  alias Core.Patient
  alias Core.Patients

  describe "create package" do
    test "patient not found", %{conn: conn} do
      conn = post(conn, diagnostic_report_path(conn, :create, UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      conn = post(conn, diagnostic_report_path(conn, :create, patient_id))
      assert json_response(conn, 409)
    end

    test "no signed data set", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      conn = post(conn, diagnostic_report_path(conn, :create, patient_id))
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

    test "success", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      conn =
        post(conn, diagnostic_report_path(conn, :create, patient_id), %{
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

  describe "cancel package" do
    test "patient not found", %{conn: conn} do
      conn = post(conn, diagnostic_report_path(conn, :cancel, UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      conn = post(conn, diagnostic_report_path(conn, :cancel, patient_id))
      assert json_response(conn, 409)
    end

    test "no signed data set", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      conn = post(conn, diagnostic_report_path(conn, :cancel, patient_id))
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

    test "success", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      conn =
        post(conn, diagnostic_report_path(conn, :cancel, patient_id), %{
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

  describe "show diagnostic report" do
    test "successful show", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      diagnostic_report_1 = build(:diagnostic_report)
      diagnostic_report_2 = build(:diagnostic_report)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        diagnostic_reports: %{
          UUID.binary_to_string!(diagnostic_report_1.id.binary) => diagnostic_report_1,
          UUID.binary_to_string!(diagnostic_report_2.id.binary) => diagnostic_report_2
        }
      )

      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(diagnostic_report_path(conn, :show, patient_id, UUID.binary_to_string!(diagnostic_report_1.id.binary)))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("diagnostic_reports/diagnostic_report_show.json")

      assert get_in(resp, ~w(data id)) == UUID.binary_to_string!(diagnostic_report_1.id.binary)
      refute get_in(resp, ~w(data id)) == UUID.binary_to_string!(diagnostic_report_2.id.binary)
    end

    test "invalid patient uuid", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      expect_get_person_data_empty()

      conn
      |> get(diagnostic_report_path(conn, :show, UUID.uuid4(), UUID.uuid4()))
      |> json_response(403)
    end

    test "invalid diagnostic report uuid", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      diagnostic_report = build(:diagnostic_report)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        diagnostic_reports: %{UUID.binary_to_string!(diagnostic_report.id.binary) => diagnostic_report}
      )

      expect_get_person_data(patient_id)

      conn
      |> get(diagnostic_report_path(conn, :show, patient_id, UUID.uuid4()))
      |> json_response(404)
    end

    test "get patient when no diagnostic reports", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, diagnostic_reports: %{})
      expect_get_person_data(patient_id)

      conn
      |> get(diagnostic_report_path(conn, :show, patient_id, UUID.uuid4()))
      |> json_response(404)
    end
  end

  describe "index diagnostic reports" do
    test "successful search", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(diagnostic_report_path(conn, :index, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("diagnostic_reports/diagnostic_report_list.json")

      assert %{"page_number" => 1, "total_entries" => 2, "total_pages" => 1} = resp["paging"]
    end

    test "successful search with search parameters: encounter_id", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      encounter_id = UUID.uuid4()
      encounter = build_encounter_context(Mongo.string_to_uuid(encounter_id))
      diagnostic_report_1 = build(:diagnostic_report, encounter: encounter)
      diagnostic_report_2 = build(:diagnostic_report)

      diagnostic_reports =
        [diagnostic_report_1, diagnostic_report_2]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = diagnostic_report ->
          {UUID.binary_to_string!(id), diagnostic_report}
        end)

      insert(:patient, _id: patient_id_hash, diagnostic_reports: diagnostic_reports)
      expect_get_person_data(patient_id)

      search_params = %{"encounter_id" => encounter_id}

      resp =
        conn
        |> get(diagnostic_report_path(conn, :index, patient_id), search_params)
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("diagnostic_reports/diagnostic_report_list.json")

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      resp =
        resp
        |> Map.get("data")
        |> hd()

      refute Map.get(resp, "id") == UUID.binary_to_string!(diagnostic_report_2.id.binary)
      assert Map.get(resp, "id") == UUID.binary_to_string!(diagnostic_report_1.id.binary)
      assert get_in(resp, ~w(encounter identifier value)) == encounter_id
    end

    test "successful search with search parameters: code", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      code_value = "1"

      code =
        build(
          :codeable_concept,
          coding: [build(:coding, code: code_value, system: "eHealth/LOINC/diagnostic_report_codes")]
        )

      diagnostic_report_1 = build(:diagnostic_report, code: code)
      diagnostic_report_2 = build(:diagnostic_report)

      diagnostic_reports =
        [diagnostic_report_1, diagnostic_report_2]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = diagnostic_report ->
          {UUID.binary_to_string!(id), diagnostic_report}
        end)

      insert(:patient, _id: patient_id_hash, diagnostic_reports: diagnostic_reports)
      expect_get_person_data(patient_id)

      search_params = %{"code" => code_value}

      resp =
        conn
        |> get(diagnostic_report_path(conn, :index, patient_id), search_params)
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("diagnostic_reports/diagnostic_report_list.json")

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      resp =
        resp
        |> Map.get("data")
        |> hd()

      assert Map.get(resp, "id") == UUID.binary_to_string!(diagnostic_report_1.id.binary)
      refute Map.get(resp, "id") == UUID.binary_to_string!(diagnostic_report_2.id.binary)
    end

    test "successful search with search parameters: context_episode_id", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      episode_1 = build(:episode)
      episode_2 = build(:episode)

      encounter_1 = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode_1.id)))
      encounter_2 = build(:encounter)

      encounter = build_encounter_context(encounter_1.id)
      diagnostic_report_1 = build(:diagnostic_report, encounter: encounter)
      diagnostic_report_2 = build(:diagnostic_report)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{
          UUID.binary_to_string!(episode_1.id.binary) => episode_1,
          UUID.binary_to_string!(episode_2.id.binary) => episode_2
        },
        encounters: %{
          UUID.binary_to_string!(encounter_1.id.binary) => encounter_1,
          UUID.binary_to_string!(encounter_2.id.binary) => encounter_2
        },
        diagnostic_reports: %{
          UUID.binary_to_string!(diagnostic_report_1.id.binary) => diagnostic_report_1,
          UUID.binary_to_string!(diagnostic_report_2.id.binary) => diagnostic_report_2
        }
      )

      expect_get_person_data(patient_id)

      search_params = %{"context_episode_id" => UUID.binary_to_string!(episode_1.id.binary)}

      resp =
        conn
        |> get(diagnostic_report_path(conn, :index, patient_id), search_params)
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("diagnostic_reports/diagnostic_report_list.json")

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      resp =
        resp
        |> Map.get("data")
        |> hd()

      assert Map.get(resp, "id") == UUID.binary_to_string!(diagnostic_report_1.id.binary)
      refute Map.get(resp, "id") == UUID.binary_to_string!(diagnostic_report_2.id.binary)
    end

    test "successful search with search parameters: origin_episode_id", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      origin_episode_id = UUID.uuid4()

      origin_episode =
        build(:reference,
          identifier:
            build(:identifier,
              type: codeable_concept_coding(code: "episode"),
              value: Mongo.string_to_uuid(origin_episode_id)
            )
        )

      diagnostic_report_1 = build(:diagnostic_report, origin_episode: origin_episode)
      diagnostic_report_2 = build(:diagnostic_report)

      diagnostic_reports =
        [diagnostic_report_1, diagnostic_report_2]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = diagnostic_report ->
          {UUID.binary_to_string!(id), diagnostic_report}
        end)

      insert(:patient, _id: patient_id_hash, diagnostic_reports: diagnostic_reports)
      expect_get_person_data(patient_id)

      search_params = %{"origin_episode_id" => origin_episode_id}

      resp =
        conn
        |> get(diagnostic_report_path(conn, :index, patient_id), search_params)
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("diagnostic_reports/diagnostic_report_list.json")

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      resp =
        resp
        |> Map.get("data")
        |> hd()

      assert Map.get(resp, "id") == UUID.binary_to_string!(diagnostic_report_1.id.binary)
      refute Map.get(resp, "id") == UUID.binary_to_string!(diagnostic_report_2.id.binary)
    end

    test "successful search with search parameters: date", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      issued_from = Date.utc_today() |> Date.add(-20) |> Date.to_iso8601()
      issued_to = Date.utc_today() |> Date.add(-10) |> Date.to_iso8601()

      diagnostic_report_1 = build(:diagnostic_report, issued: get_datetime(-30))
      diagnostic_report_2 = build(:diagnostic_report, issued: get_datetime(-20))
      diagnostic_report_3 = build(:diagnostic_report, issued: get_datetime(-15))
      diagnostic_report_4 = build(:diagnostic_report, issued: get_datetime(-10))
      diagnostic_report_5 = build(:diagnostic_report, issued: get_datetime(-5))

      diagnostic_reports =
        [
          diagnostic_report_1,
          diagnostic_report_2,
          diagnostic_report_3,
          diagnostic_report_4,
          diagnostic_report_5
        ]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = diagnostic_report ->
          {UUID.binary_to_string!(id), diagnostic_report}
        end)

      insert(:patient, _id: patient_id_hash, diagnostic_reports: diagnostic_reports)
      expect_get_person_data(patient_id, 4)

      call_endpoint = fn search_params ->
        conn
        |> get(diagnostic_report_path(conn, :index, patient_id), search_params)
        |> json_response(200)
      end

      # both dates
      assert %{"page_number" => 1, "total_entries" => 3, "total_pages" => 1} =
               call_endpoint.(%{
                 "issued_from" => issued_from,
                 "issued_to" => issued_to
               })
               |> Map.get("paging")

      # date_from only
      assert %{"page_number" => 1, "total_entries" => 4, "total_pages" => 1} =
               call_endpoint.(%{"issued_from" => issued_from})
               |> Map.get("paging")

      # date_to only
      assert %{"page_number" => 1, "total_entries" => 4, "total_pages" => 1} =
               call_endpoint.(%{"issued_to" => issued_to})
               |> Map.get("paging")

      # without date search params
      assert %{"page_number" => 1, "total_entries" => 5, "total_pages" => 1} =
               call_endpoint.(%{})
               |> Map.get("paging")
    end

    test "successful search with search parameters: based_on", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      service_request_id = UUID.uuid4()

      based_on =
        build(:reference,
          identifier:
            build(:identifier,
              type: codeable_concept_coding(system: "eHealth/resources", code: "service_request"),
              value: Mongo.string_to_uuid(service_request_id)
            )
        )

      diagnostic_report_1 = build(:diagnostic_report, based_on: based_on)
      diagnostic_report_2 = build(:diagnostic_report)

      diagnostic_reports =
        [diagnostic_report_1, diagnostic_report_2]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = diagnostic_report ->
          {UUID.binary_to_string!(id), diagnostic_report}
        end)

      insert(:patient, _id: patient_id_hash, diagnostic_reports: diagnostic_reports)
      expect_get_person_data(patient_id)

      search_params = %{"based_on" => service_request_id}

      resp =
        conn
        |> get(diagnostic_report_path(conn, :index, patient_id), search_params)
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("diagnostic_reports/diagnostic_report_list.json")

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      resp =
        resp
        |> Map.get("data")
        |> hd()

      assert Map.get(resp, "id") == UUID.binary_to_string!(diagnostic_report_1.id.binary)
      refute Map.get(resp, "id") == UUID.binary_to_string!(diagnostic_report_2.id.binary)
    end

    test "successful search with search parameters: complex test", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      code_value = "1"

      code =
        build(
          :codeable_concept,
          coding: [
            build(:coding, code: code_value, system: "eHealth/diagnostic_report_medications"),
            build(:coding, code: "test", system: "eHealth/diagnostic_report_medications")
          ]
        )

      issued_from = Date.utc_today() |> Date.add(-20) |> Date.to_iso8601()
      issued_to = Date.utc_today() |> Date.add(-10) |> Date.to_iso8601()

      encounter_id_1 = UUID.uuid4()
      context_encounter_id = build_encounter_context(Mongo.string_to_uuid(encounter_id_1))

      episode = build(:episode)
      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))
      encounter_id_2 = UUID.binary_to_string!(encounter.id.binary)
      context_episode_id = build_encounter_context(Mongo.string_to_uuid(encounter_id_2))

      origin_episode_id = UUID.uuid4()

      origin_episode =
        build(:reference,
          identifier:
            build(:identifier,
              type: codeable_concept_coding(code: "episode"),
              value: Mongo.string_to_uuid(origin_episode_id)
            )
        )

      diagnostic_report_1 =
        build(:diagnostic_report,
          encounter: context_encounter_id,
          code: code,
          issued: get_datetime(-15),
          origin_episode: origin_episode
        )

      diagnostic_report_2 = build(:diagnostic_report, encounter: context_encounter_id, issued: get_datetime(-15))

      diagnostic_report_3 = build(:diagnostic_report, code: code, issued: get_datetime(-15))

      diagnostic_report_4 =
        build(:diagnostic_report,
          encounter: context_episode_id,
          code: code,
          issued: get_datetime(-15),
          origin_episode: origin_episode
        )

      diagnostic_report_5 = build(:diagnostic_report, issued: get_datetime(-30))
      diagnostic_report_6 = build(:diagnostic_report, issued: get_datetime(-15))
      diagnostic_report_7 = build(:diagnostic_report, issued: get_datetime(-5))

      diagnostic_reports =
        [
          diagnostic_report_1,
          diagnostic_report_2,
          diagnostic_report_3,
          diagnostic_report_4,
          diagnostic_report_5,
          diagnostic_report_6,
          diagnostic_report_7
        ]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = diagnostic_report ->
          {UUID.binary_to_string!(id), diagnostic_report}
        end)

      insert(
        :patient,
        _id: patient_id_hash,
        diagnostic_reports: diagnostic_reports,
        episodes: %{
          UUID.binary_to_string!(episode.id.binary) => episode
        },
        encounters: %{
          UUID.binary_to_string!(encounter.id.binary) => encounter
        }
      )

      expect_get_person_data(patient_id, 4)

      search_params = %{
        "encounter_id" => encounter_id_1,
        "code" => code_value,
        "origin_episode_id" => origin_episode_id,
        "context_episode_id" => UUID.binary_to_string!(episode.id.binary),
        "issued_from" => issued_from,
        "issued_to" => issued_to
      }

      call_endpoint = fn search_params ->
        conn
        |> get(diagnostic_report_path(conn, :index, patient_id), search_params)
        |> json_response(200)
      end

      # all params
      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} =
               call_endpoint.(search_params)
               |> Map.get("paging")

      # all params except encounter_id
      resp = call_endpoint.(Map.delete(search_params, "encounter_id"))

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      resp =
        resp
        |> Map.get("data")
        |> hd()

      assert Map.get(resp, "id") == UUID.binary_to_string!(diagnostic_report_4.id.binary)
      assert get_in(resp, ~w(encounter identifier value)) == encounter_id_2

      # all params except context_episode_id
      resp = call_endpoint.(Map.delete(search_params, "context_episode_id"))

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      resp =
        resp
        |> Map.get("data")
        |> hd()

      assert Map.get(resp, "id") == UUID.binary_to_string!(diagnostic_report_1.id.binary)
      assert get_in(resp, ~w(encounter identifier value)) == encounter_id_1
    end

    test "empty search list when episode_id not found in encounters", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      episode_1 = build(:episode)
      episode_2 = build(:episode)

      encounter_1 = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode_1.id)))
      encounter_2 = build(:encounter)

      encounter = build_encounter_context(encounter_1.id)
      diagnostic_report_1 = build(:diagnostic_report, encounter: encounter)
      diagnostic_report_2 = build(:diagnostic_report)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{
          UUID.binary_to_string!(episode_1.id.binary) => episode_1,
          UUID.binary_to_string!(episode_2.id.binary) => episode_2
        },
        encounters: %{
          UUID.binary_to_string!(encounter_1.id.binary) => encounter_1,
          UUID.binary_to_string!(encounter_2.id.binary) => encounter_2
        },
        diagnostic_reports: %{
          UUID.binary_to_string!(diagnostic_report_1.id.binary) => diagnostic_report_1,
          UUID.binary_to_string!(diagnostic_report_2.id.binary) => diagnostic_report_2
        }
      )

      expect_get_person_data(patient_id)

      search_params = %{"context_episode_id" => UUID.uuid4()}

      resp =
        conn
        |> get(diagnostic_report_path(conn, :index, patient_id), search_params)
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("diagnostic_reports/diagnostic_report_list.json")

      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end

    test "invalid search params", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      expect_get_person_data(patient_id)

      search_params = %{
        "encounter_id" => "test",
        "code" => 12345,
        "origin_episode_id" => "test",
        "context_episode_id" => "test",
        "issued_from" => "2018-02-31",
        "issued_to" => "2018-8-t"
      }

      resp =
        conn
        |> get(diagnostic_report_path(conn, :index, patient_id), search_params)
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.code",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "type mismatch. Expected String but got Integer",
                       "params" => ["string"],
                       "rule" => "cast"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.context_episode_id",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" =>
                         "string does not match pattern \"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$\"",
                       "params" => ["^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"],
                       "rule" => "format"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.encounter_id",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" =>
                         "string does not match pattern \"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$\"",
                       "params" => ["^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"],
                       "rule" => "format"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.issued_from",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "expected \"2018-02-31\" to be an existing date",
                       "params" => [],
                       "rule" => "date"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.issued_to",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "expected \"2018-8-t\" to be a valid ISO 8601 date",
                       "params" => [
                         "~r/^([\\+-]?\\d{4}(?!\\d{2}\\b))((-?)((0[1-9]|1[0-2])(\\3([12]\\d|0[1-9]|3[01]))?|W([0-4]\\d|5[0-2])(-?[1-7])?|(00[1-9]|0[1-9]\\d|[12]\\d{2}|3([0-5]\\d|6[1-6])))?)?$/"
                       ],
                       "rule" => "date"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.origin_episode_id",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" =>
                         "string does not match pattern \"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$\"",
                       "params" => ["^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"],
                       "rule" => "format"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "invalid patient uuid", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      expect_get_person_data_empty()

      conn
      |> get(diagnostic_report_path(conn, :index, UUID.uuid4()))
      |> json_response(403)
    end

    test "get patient when no diagnostic_reports", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, diagnostic_reports: %{})
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(diagnostic_report_path(conn, :index, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("diagnostic_reports/diagnostic_report_list.json")

      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end

    test "get patient when diagnostic_reports list is null", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, diagnostic_reports: nil)
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(diagnostic_report_path(conn, :index, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("diagnostic_reports/diagnostic_report_list.json")

      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end
  end

  defp build_encounter_context(encounter_id) do
    build(
      :reference,
      identifier: build(:identifier, value: encounter_id, type: codeable_concept_coding(code: "encounter"))
    )
  end

  defp get_datetime(day_shift) do
    date = Date.utc_today() |> Date.add(day_shift) |> Date.to_erl()
    {date, {0, 0, 0}} |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
  end
end
