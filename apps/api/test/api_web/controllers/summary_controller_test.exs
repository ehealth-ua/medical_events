defmodule Api.Web.SummaryControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase
  alias Core.Observations.Value
  alias Core.Patients
  import Core.DateTime
  import Mox

  setup :verify_on_exit!

  describe "list episodes" do
    test "successful search", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      resp =
        conn
        |> get(summary_path(conn, :list_episodes, patient_id))
        |> json_response(200)

      Enum.each(resp["data"], fn episode ->
        assert_json_schema(episode, "episodes/episode_summary.json")
      end)

      assert %{"page_number" => 1, "total_entries" => 2, "total_pages" => 1} = resp["paging"]
    end

    test "invalid search parameters", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      search_params = %{"code" => "123", "service_request_id" => UUID.uuid4()}

      resp =
        conn
        |> get(summary_path(conn, :list_episodes, patient_id), search_params)
        |> json_response(422)

      assert [
               %{
                 "entry" => "$.code",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               },
               %{
                 "entry" => "$.service_request_id",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               }
             ] = resp["error"]["invalid"]
    end

    test "successful search with search parameters: period", %{conn: conn} do
      week_ago = create_datetime(Date.add(Date.utc_today(), -7))
      next_week = create_datetime(Date.add(Date.utc_today(), 7))
      tomorrow = create_datetime(Date.add(Date.utc_today(), +1))
      yesterday = create_datetime(Date.add(Date.utc_today(), -1))
      today = create_datetime(Date.utc_today())

      tomorrow_inactive_episode = build(:episode, period: build(:period, start: tomorrow, end: tomorrow))
      tomorrow_active_episode = build(:episode, period: build(:period, start: tomorrow, end: next_week))

      today_inactive_episode = build(:episode, period: build(:period, start: today, end: tomorrow))
      today_active_episode = build(:episode, period: build(:period, start: today, end: next_week))

      week_ago_inactive_episode = build(:episode, period: build(:period, start: week_ago, end: yesterday))
      week_ago_today_episode = build(:episode, period: build(:period, start: week_ago, end: today))
      week_ago_next_week_episode = build(:episode, period: build(:period, start: week_ago, end: next_week))

      week_ago_noend_episode = build(:episode, period: build(:period, start: week_ago, end: nil))
      today_noend_episode = build(:episode, period: build(:period, start: today, end: nil))
      tomorrow_noend_episode = build(:episode, period: build(:period, start: tomorrow, end: nil))
      next_week_noend_episode = build(:episode, period: build(:period, start: next_week, end: nil))

      builded_episodes = [
        tomorrow_inactive_episode,
        tomorrow_active_episode,
        today_inactive_episode,
        today_active_episode,
        week_ago_inactive_episode,
        week_ago_today_episode,
        week_ago_next_week_episode,
        week_ago_noend_episode,
        today_noend_episode,
        tomorrow_noend_episode,
        next_week_noend_episode
      ]

      episodes =
        Enum.reduce(builded_episodes, %{}, fn episode, episodes ->
          Map.put(episodes, UUID.binary_to_string!(episode.id.binary), episode)
        end)

      episode_id = fn episode ->
        UUID.binary_to_string!(episode.id.binary)
      end

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, episodes: episodes, _id: patient_id_hash)

      resp =
        conn
        |> get(summary_path(conn, :list_episodes, patient_id), %{
          "period_from" => yesterday |> DateTime.to_date() |> Date.to_string(),
          "period_to" => today |> DateTime.to_date() |> Date.to_string()
        })
        |> json_response(200)

      ids =
        Enum.reduce(resp["data"], [], fn episode, ids ->
          assert_json_schema(episode, "episodes/episode_summary.json")
          [episode["id"] | ids]
        end)

      assert_matching_ids(ids, [
        episode_id.(today_inactive_episode),
        episode_id.(today_active_episode),
        episode_id.(week_ago_inactive_episode),
        episode_id.(week_ago_today_episode),
        episode_id.(week_ago_next_week_episode),
        episode_id.(week_ago_noend_episode),
        episode_id.(today_noend_episode)
      ])
    end
  end

  describe "list immunizations" do
    test "successful search", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      resp =
        conn
        |> get(summary_path(conn, :list_immunizations, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("immunizations/immunization_list.json")

      assert %{"page_number" => 1, "total_entries" => 2, "total_pages" => 1} = resp["paging"]
    end

    test "invalid search parameters", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      search_params = %{"encounter_id" => UUID.uuid4(), "episode_id" => UUID.uuid4()}

      resp =
        conn
        |> get(summary_path(conn, :list_immunizations, patient_id), search_params)
        |> json_response(422)

      assert [
               %{
                 "entry" => "$.encounter_id",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               },
               %{
                 "entry" => "$.episode_id",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               }
             ] = resp["error"]["invalid"]
    end

    test "successful search with search parameters: vaccine_code", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      code = "wex-10"

      vaccine_code =
        build(
          :codeable_concept,
          coding: [
            build(:coding, code: code, system: "eHealth/vaccine_codes"),
            build(:coding, code: "test", system: "eHealth/vaccine_codes")
          ]
        )

      immunization_1 = build(:immunization, vaccine_code: vaccine_code)
      immunization_2 = build(:immunization)

      immunizations =
        [immunization_1, immunization_2]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = immunization ->
          {UUID.binary_to_string!(id), immunization}
        end)

      insert(:patient, _id: patient_id_hash, immunizations: immunizations)

      search_params = %{"vaccine_code" => code}

      resp =
        conn
        |> get(summary_path(conn, :list_immunizations, patient_id), search_params)
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("immunizations/immunization_list.json")

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      resp =
        resp
        |> Map.get("data")
        |> hd()

      assert Map.get(resp, "id") == UUID.binary_to_string!(immunization_1.id.binary)
      refute Map.get(resp, "id") == UUID.binary_to_string!(immunization_2.id.binary)
    end

    test "successful search with search parameters: date", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      date_from = Date.utc_today() |> Date.add(-20) |> Date.to_iso8601()
      date_to = Date.utc_today() |> Date.add(-10) |> Date.to_iso8601()

      immunization_1 = build(:immunization, date: get_datetime(-30))
      immunization_2 = build(:immunization, date: get_datetime(-20))
      immunization_3 = build(:immunization, date: get_datetime(-15))
      immunization_4 = build(:immunization, date: get_datetime(-10))
      immunization_5 = build(:immunization, date: get_datetime(-5))

      immunizations =
        [immunization_1, immunization_2, immunization_3, immunization_4, immunization_5]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = immunization ->
          {UUID.binary_to_string!(id), immunization}
        end)

      insert(:patient, _id: patient_id_hash, immunizations: immunizations)

      call_endpoint = fn search_params ->
        conn
        |> get(summary_path(conn, :list_immunizations, patient_id), search_params)
        |> json_response(200)
      end

      # both dates
      assert %{"page_number" => 1, "total_entries" => 3, "total_pages" => 1} =
               call_endpoint.(%{"date_from" => date_from, "date_to" => date_to})
               |> Map.get("paging")

      # date_from only
      assert %{"page_number" => 1, "total_entries" => 4, "total_pages" => 1} =
               call_endpoint.(%{"date_from" => date_from})
               |> Map.get("paging")

      # date_to only
      assert %{"page_number" => 1, "total_entries" => 4, "total_pages" => 1} =
               call_endpoint.(%{"date_to" => date_to})
               |> Map.get("paging")

      # without date search params
      assert %{"page_number" => 1, "total_entries" => 5, "total_pages" => 1} =
               call_endpoint.(%{})
               |> Map.get("paging")
    end

    test "get patient when immunizations list is null", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, immunizations: nil)

      resp =
        conn
        |> get(summary_path(conn, :list_immunizations, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("immunizations/immunization_list.json")

      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end
  end

  describe "list allergy intolerances" do
    test "successful search", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      resp =
        conn
        |> get(summary_path(conn, :list_allergy_intolerances, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("allergy_intolerances/allergy_intolerance_list.json")

      assert %{"page_number" => 1, "total_entries" => 2, "total_pages" => 1} = resp["paging"]
    end

    test "invalid search parameters", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      search_params = %{"encounter_id" => UUID.uuid4(), "episode_id" => UUID.uuid4()}

      resp =
        conn
        |> get(summary_path(conn, :list_allergy_intolerances, patient_id), search_params)
        |> json_response(422)

      assert [
               %{
                 "entry" => "$.encounter_id",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               },
               %{
                 "entry" => "$.episode_id",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               }
             ] = resp["error"]["invalid"]
    end

    test "successful search with search parameters: code", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      code_value = "1"

      code =
        build(
          :codeable_concept,
          coding: [build(:coding, code: code_value, system: "eHealth/allergy_intolerance_codes")]
        )

      allergy_intolerance_1 = build(:allergy_intolerance, code: code)
      allergy_intolerance_2 = build(:allergy_intolerance)

      allergy_intolerances =
        [allergy_intolerance_1, allergy_intolerance_2]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = allergy_intolerance ->
          {UUID.binary_to_string!(id), allergy_intolerance}
        end)

      insert(:patient, _id: patient_id_hash, allergy_intolerances: allergy_intolerances)

      search_params = %{"code" => code_value}

      resp =
        conn
        |> get(summary_path(conn, :list_allergy_intolerances, patient_id), search_params)
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("allergy_intolerances/allergy_intolerance_list.json")

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      resp =
        resp
        |> Map.get("data")
        |> hd()

      assert Map.get(resp, "id") == UUID.binary_to_string!(allergy_intolerance_1.id.binary)
      refute Map.get(resp, "id") == UUID.binary_to_string!(allergy_intolerance_2.id.binary)
    end

    test "successful search with search parameters: date", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      onset_date_time_from = Date.utc_today() |> Date.add(-20) |> Date.to_iso8601()
      onset_date_time_to = Date.utc_today() |> Date.add(-10) |> Date.to_iso8601()

      allergy_intolerance_1 = build(:allergy_intolerance, onset_date_time: get_datetime(-30))
      allergy_intolerance_2 = build(:allergy_intolerance, onset_date_time: get_datetime(-20))
      allergy_intolerance_3 = build(:allergy_intolerance, onset_date_time: get_datetime(-15))
      allergy_intolerance_4 = build(:allergy_intolerance, onset_date_time: get_datetime(-10))
      allergy_intolerance_5 = build(:allergy_intolerance, onset_date_time: get_datetime(-5))

      allergy_intolerances =
        [
          allergy_intolerance_1,
          allergy_intolerance_2,
          allergy_intolerance_3,
          allergy_intolerance_4,
          allergy_intolerance_5
        ]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = allergy_intolerance ->
          {UUID.binary_to_string!(id), allergy_intolerance}
        end)

      insert(:patient, _id: patient_id_hash, allergy_intolerances: allergy_intolerances)

      call_endpoint = fn search_params ->
        conn
        |> get(summary_path(conn, :list_allergy_intolerances, patient_id), search_params)
        |> json_response(200)
      end

      # both dates
      assert %{"page_number" => 1, "total_entries" => 3, "total_pages" => 1} =
               call_endpoint.(%{
                 "onset_date_time_from" => onset_date_time_from,
                 "onset_date_time_to" => onset_date_time_to
               })
               |> Map.get("paging")

      # date_from only
      assert %{"page_number" => 1, "total_entries" => 4, "total_pages" => 1} =
               call_endpoint.(%{"onset_date_time_from" => onset_date_time_from})
               |> Map.get("paging")

      # date_to only
      assert %{"page_number" => 1, "total_entries" => 4, "total_pages" => 1} =
               call_endpoint.(%{"onset_date_time_to" => onset_date_time_to})
               |> Map.get("paging")

      # without date search params
      assert %{"page_number" => 1, "total_entries" => 5, "total_pages" => 1} =
               call_endpoint.(%{})
               |> Map.get("paging")
    end

    test "get patient when allergy intolerances list is null", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, allergy_intolerances: nil)

      resp =
        conn
        |> get(summary_path(conn, :list_allergy_intolerances, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("allergy_intolerances/allergy_intolerance_list.json")

      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end
  end

  describe "list risk assessments" do
    test "successful search", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      resp =
        conn
        |> get(summary_path(conn, :list_risk_assessments, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("risk_assessments/risk_assessment_list.json")

      assert %{"page_number" => 1, "total_entries" => 2, "total_pages" => 1} = resp["paging"]
    end

    test "invalid search parameters", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      search_params = %{"encounter_id" => UUID.uuid4(), "episode_id" => UUID.uuid4()}

      resp =
        conn
        |> get(summary_path(conn, :list_risk_assessments, patient_id), search_params)
        |> json_response(422)

      assert [
               %{
                 "entry" => "$.encounter_id",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               },
               %{
                 "entry" => "$.episode_id",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               }
             ] = resp["error"]["invalid"]
    end

    test "successful search with search parameters: code", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      code_value = "1"

      code =
        build(
          :codeable_concept,
          coding: [build(:coding, code: code_value, system: "eHealth/risk_assessment_codes")]
        )

      risk_assessment_1 = build(:risk_assessment, code: code)
      risk_assessment_2 = build(:risk_assessment)

      risk_assessments =
        [risk_assessment_1, risk_assessment_2]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = risk_assessment ->
          {UUID.binary_to_string!(id), risk_assessment}
        end)

      insert(:patient, _id: patient_id_hash, risk_assessments: risk_assessments)

      search_params = %{"code" => code_value}

      resp =
        conn
        |> get(summary_path(conn, :list_risk_assessments, patient_id), search_params)
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("risk_assessments/risk_assessment_list.json")

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      resp =
        resp
        |> Map.get("data")
        |> hd()

      assert Map.get(resp, "id") == UUID.binary_to_string!(risk_assessment_1.id.binary)
      refute Map.get(resp, "id") == UUID.binary_to_string!(risk_assessment_2.id.binary)
    end

    test "successful search with search parameters: date", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      asserted_date_from = Date.utc_today() |> Date.add(-20) |> Date.to_iso8601()
      asserted_date_to = Date.utc_today() |> Date.add(-10) |> Date.to_iso8601()

      risk_assessment_1 = build(:risk_assessment, asserted_date: get_datetime(-30))
      risk_assessment_2 = build(:risk_assessment, asserted_date: get_datetime(-20))
      risk_assessment_3 = build(:risk_assessment, asserted_date: get_datetime(-15))
      risk_assessment_4 = build(:risk_assessment, asserted_date: get_datetime(-10))
      risk_assessment_5 = build(:risk_assessment, asserted_date: get_datetime(-5))

      risk_assessments =
        [
          risk_assessment_1,
          risk_assessment_2,
          risk_assessment_3,
          risk_assessment_4,
          risk_assessment_5
        ]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = risk_assessment ->
          {UUID.binary_to_string!(id), risk_assessment}
        end)

      insert(:patient, _id: patient_id_hash, risk_assessments: risk_assessments)

      call_endpoint = fn search_params ->
        conn
        |> get(summary_path(conn, :list_risk_assessments, patient_id), search_params)
        |> json_response(200)
      end

      # both dates
      assert %{"page_number" => 1, "total_entries" => 3, "total_pages" => 1} =
               call_endpoint.(%{
                 "asserted_date_from" => asserted_date_from,
                 "asserted_date_to" => asserted_date_to
               })
               |> Map.get("paging")

      # date_from only
      assert %{"page_number" => 1, "total_entries" => 4, "total_pages" => 1} =
               call_endpoint.(%{"asserted_date_from" => asserted_date_from})
               |> Map.get("paging")

      # date_to only
      assert %{"page_number" => 1, "total_entries" => 4, "total_pages" => 1} =
               call_endpoint.(%{"asserted_date_to" => asserted_date_to})
               |> Map.get("paging")

      # without date search params
      assert %{"page_number" => 1, "total_entries" => 5, "total_pages" => 1} =
               call_endpoint.(%{})
               |> Map.get("paging")
    end

    test "get patient when risk assessments list is null", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, risk_assessments: nil)

      resp =
        conn
        |> get(summary_path(conn, :list_risk_assessments, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("risk_assessments/risk_assessment_list.json")

      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end
  end

  describe "list devices" do
    test "successful search", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      resp =
        conn
        |> get(summary_path(conn, :list_devices, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("devices/device_list.json")

      assert %{"page_number" => 1, "total_entries" => 2, "total_pages" => 1} = resp["paging"]
    end

    test "invalid search parameters", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      search_params = %{"encounter_id" => UUID.uuid4(), "episode_id" => UUID.uuid4()}

      resp =
        conn
        |> get(summary_path(conn, :list_devices, patient_id), search_params)
        |> json_response(422)

      assert [
               %{
                 "entry" => "$.encounter_id",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               },
               %{
                 "entry" => "$.episode_id",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               }
             ] = resp["error"]["invalid"]
    end

    test "successful search with search parameters: type", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      type_value = "1"

      type =
        build(
          :codeable_concept,
          coding: [build(:coding, code: type_value, system: "eHealth/device_types")]
        )

      device_1 = build(:device, type: type)
      device_2 = build(:device)

      devices =
        [device_1, device_2]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = device ->
          {UUID.binary_to_string!(id), device}
        end)

      insert(:patient, _id: patient_id_hash, devices: devices)

      search_params = %{"type" => type_value}

      resp =
        conn
        |> get(summary_path(conn, :list_devices, patient_id), search_params)
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("devices/device_list.json")

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      resp =
        resp
        |> Map.get("data")
        |> hd()

      assert Map.get(resp, "id") == UUID.binary_to_string!(device_1.id.binary)
      refute Map.get(resp, "id") == UUID.binary_to_string!(device_2.id.binary)
    end

    test "successful search with search parameters: date", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      asserted_date_from = Date.utc_today() |> Date.add(-20) |> Date.to_iso8601()
      asserted_date_to = Date.utc_today() |> Date.add(-10) |> Date.to_iso8601()

      device_1 = build(:device, asserted_date: get_datetime(-30))
      device_2 = build(:device, asserted_date: get_datetime(-20))
      device_3 = build(:device, asserted_date: get_datetime(-15))
      device_4 = build(:device, asserted_date: get_datetime(-10))
      device_5 = build(:device, asserted_date: get_datetime(-5))

      devices =
        [
          device_1,
          device_2,
          device_3,
          device_4,
          device_5
        ]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = device ->
          {UUID.binary_to_string!(id), device}
        end)

      insert(:patient, _id: patient_id_hash, devices: devices)

      call_endpoint = fn search_params ->
        conn
        |> get(summary_path(conn, :list_devices, patient_id), search_params)
        |> json_response(200)
      end

      # both dates
      assert %{"page_number" => 1, "total_entries" => 3, "total_pages" => 1} =
               call_endpoint.(%{
                 "asserted_date_from" => asserted_date_from,
                 "asserted_date_to" => asserted_date_to
               })
               |> Map.get("paging")

      # date_from only
      assert %{"page_number" => 1, "total_entries" => 4, "total_pages" => 1} =
               call_endpoint.(%{"asserted_date_from" => asserted_date_from})
               |> Map.get("paging")

      # date_to only
      assert %{"page_number" => 1, "total_entries" => 4, "total_pages" => 1} =
               call_endpoint.(%{"asserted_date_to" => asserted_date_to})
               |> Map.get("paging")

      # without date search params
      assert %{"page_number" => 1, "total_entries" => 5, "total_pages" => 1} =
               call_endpoint.(%{})
               |> Map.get("paging")
    end

    test "get patient when devices list is null", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, devices: nil)

      resp =
        conn
        |> get(summary_path(conn, :list_devices, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("devices/device_list.json")

      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end
  end

  describe "list medication statements" do
    test "successful search", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      resp =
        conn
        |> get(summary_path(conn, :list_medication_statements, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("medication_statements/medication_statement_list.json")

      assert %{"page_number" => 1, "total_entries" => 2, "total_pages" => 1} = resp["paging"]
    end

    test "invalid search parameters", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      search_params = %{"encounter_id" => UUID.uuid4(), "episode_id" => UUID.uuid4()}

      resp =
        conn
        |> get(summary_path(conn, :list_medication_statements, patient_id), search_params)
        |> json_response(422)

      assert [
               %{
                 "entry" => "$.encounter_id",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               },
               %{
                 "entry" => "$.episode_id",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               }
             ] = resp["error"]["invalid"]
    end

    test "successful search with search parameters: medication_code", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      medication_code_value = "1"

      medication_code =
        build(
          :codeable_concept,
          coding: [build(:coding, code: medication_code_value, system: "eHealth/medication_statement_medications")]
        )

      medication_statement_1 = build(:medication_statement, medication_code: medication_code)
      medication_statement_2 = build(:medication_statement)

      medication_statements =
        [medication_statement_1, medication_statement_2]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = medication_statement ->
          {UUID.binary_to_string!(id), medication_statement}
        end)

      insert(:patient, _id: patient_id_hash, medication_statements: medication_statements)

      search_params = %{"medication_code" => medication_code_value}

      resp =
        conn
        |> get(summary_path(conn, :list_medication_statements, patient_id), search_params)
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("medication_statements/medication_statement_list.json")

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      resp =
        resp
        |> Map.get("data")
        |> hd()

      assert Map.get(resp, "id") == UUID.binary_to_string!(medication_statement_1.id.binary)
      refute Map.get(resp, "id") == UUID.binary_to_string!(medication_statement_2.id.binary)
    end

    test "successful search with search parameters: date", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      asserted_date_from = Date.utc_today() |> Date.add(-20) |> Date.to_iso8601()
      asserted_date_to = Date.utc_today() |> Date.add(-10) |> Date.to_iso8601()

      medication_statement_1 = build(:medication_statement, asserted_date: get_datetime(-30))
      medication_statement_2 = build(:medication_statement, asserted_date: get_datetime(-20))
      medication_statement_3 = build(:medication_statement, asserted_date: get_datetime(-15))
      medication_statement_4 = build(:medication_statement, asserted_date: get_datetime(-10))
      medication_statement_5 = build(:medication_statement, asserted_date: get_datetime(-5))

      medication_statements =
        [
          medication_statement_1,
          medication_statement_2,
          medication_statement_3,
          medication_statement_4,
          medication_statement_5
        ]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = medication_statement ->
          {UUID.binary_to_string!(id), medication_statement}
        end)

      insert(:patient, _id: patient_id_hash, medication_statements: medication_statements)

      call_endpoint = fn search_params ->
        conn
        |> get(summary_path(conn, :list_medication_statements, patient_id), search_params)
        |> json_response(200)
      end

      # both dates
      assert %{"page_number" => 1, "total_entries" => 3, "total_pages" => 1} =
               call_endpoint.(%{
                 "asserted_date_from" => asserted_date_from,
                 "asserted_date_to" => asserted_date_to
               })
               |> Map.get("paging")

      # date_from only
      assert %{"page_number" => 1, "total_entries" => 4, "total_pages" => 1} =
               call_endpoint.(%{"asserted_date_from" => asserted_date_from})
               |> Map.get("paging")

      # date_to only
      assert %{"page_number" => 1, "total_entries" => 4, "total_pages" => 1} =
               call_endpoint.(%{"asserted_date_to" => asserted_date_to})
               |> Map.get("paging")

      # without date search params
      assert %{"page_number" => 1, "total_entries" => 5, "total_pages" => 1} =
               call_endpoint.(%{})
               |> Map.get("paging")
    end

    test "get patient when medication statements list is null", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, medication_statements: nil)

      resp =
        conn
        |> get(summary_path(conn, :list_medication_statements, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("medication_statements/medication_statement_list.json")

      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end
  end

  describe "search conditions" do
    test "success by code, onset_date", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      {code, condition_code} = build_condition_code("R80")
      {_, onset_date, _} = DateTime.from_iso8601("1991-01-01 00:00:00Z")
      {_, onset_date2, _} = DateTime.from_iso8601("2010-01-01 00:00:00Z")

      insert_list(
        2,
        :condition,
        patient_id: patient_id_hash,
        code: condition_code,
        asserted_date: nil,
        onset_date: onset_date
      )

      # Missed code, encounter, patient_id
      insert(:condition, patient_id: patient_id_hash, onset_date: onset_date2)
      insert(:condition, patient_id: patient_id_hash)
      insert(:condition, patient_id: patient_id_hash)
      insert(:condition)

      request_params = %{
        "code" => code,
        "onset_date_from" => "1990-01-01",
        "onset_date_to" => "2000-01-01"
      }

      response =
        conn
        |> get(summary_path(conn, :list_conditions, patient_id), request_params)
        |> json_response(200)
        |> assert_json_schema("conditions/conditions_list.json")

      Enum.each(response["data"], fn condition ->
        assert %{"code" => %{"coding" => [%{"code" => ^code}]}} = condition
      end)

      assert 2 == response["paging"]["total_entries"]
    end

    test "invalid code", %{conn: conn} do
      episode = build(:episode)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, episodes: %{to_string(episode.id) => episode}, _id: patient_id_hash)

      {code, condition_code} = build_condition_code("A10")

      insert_list(2, :condition, patient_id: patient_id_hash, code: condition_code)

      # Missed code, patient_id
      insert(:condition, patient_id: patient_id_hash)
      insert(:condition)

      request_params = %{"code" => code}

      response =
        conn
        |> get(summary_path(conn, :list_conditions, patient_id), request_params)
        |> json_response(200)

      assert 0 == response["paging"]["total_entries"]
    end

    test "invalid search parameters", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      search_params = %{"onset_date_from" => "invalid"}

      resp =
        conn
        |> get(summary_path(conn, :list_conditions, patient_id), search_params)
        |> json_response(422)

      assert [
               %{
                 "entry" => "$.onset_date_from",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"rule" => "date"}]
               }
             ] = resp["error"]["invalid"]
    end
  end

  describe "get condition" do
    test "success", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      condition =
        insert(
          :condition,
          patient_id: patient_id_hash,
          asserted_date: nil,
          code: codeable_concept_coding(system: "eHealth/ICD10/condition_codes", code: "R80")
        )

      conn
      |> get(summary_path(conn, :show_condition, patient_id, UUID.binary_to_string!(condition._id.binary)))
      |> json_response(200)
      |> assert_json_schema("conditions/condition_show.json")
    end

    test "condition has different code", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      condition =
        insert(
          :condition,
          patient_id: patient_id_hash,
          asserted_date: nil,
          code: codeable_concept_coding(system: "eHealth/ICD10/condition_codes", code: "J11")
        )

      assert conn
             |> get(summary_path(conn, :show_condition, patient_id, UUID.binary_to_string!(condition._id.binary)))
             |> json_response(404)
    end

    test "condition not found", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      conn
      |> get(summary_path(conn, :show_condition, patient_id, UUID.uuid4()))
      |> json_response(404)
    end
  end

  describe "get observation" do
    test "success", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      observation =
        insert(
          :observation,
          patient_id: patient_id_hash,
          value: %Value{value_period: build(:period)},
          code: codeable_concept_coding(system: "eHealth/LOINC/observation_codes", code: "8310-5")
        )

      response_data =
        conn
        |> get(summary_path(conn, :show_observation, patient_id, UUID.binary_to_string!(observation._id.binary)))
        |> json_response(200)
        |> Map.get("data")
        |> assert_json_schema("observations/observation_show.json")

      assert %{"start" => _, "end" => _} = response_data["value_period"]
    end

    test "observation has different code", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      insert(:observation, patient_id: patient_id_hash)

      conn
      |> get(summary_path(conn, :show_observation, patient_id, UUID.uuid4()))
      |> json_response(404)
    end

    test "observation not found", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      conn
      |> get(summary_path(conn, :show_condition, patient_id, UUID.uuid4()))
      |> json_response(404)
    end
  end

  describe "list active diagnoses" do
    test "success", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      resp =
        conn
        |> get(summary_path(conn, :list_diagnoses, patient_id))
        |> json_response(200)

      assert %{"page_number" => 1, "total_entries" => 4, "total_pages" => 1} = resp["paging"]
    end

    test "invalid code", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      resp =
        conn
        |> get(summary_path(conn, :list_diagnoses, patient_id), %{"code" => "invalid"})
        |> json_response(200)

      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end
  end

  describe "get diagnostic report" do
    test "success", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      diagnostic_report = build(:diagnostic_report)

      insert(:patient,
        _id: patient_id_hash,
        diagnostic_reports: %{UUID.binary_to_string!(diagnostic_report.id.binary) => diagnostic_report}
      )

      conn
      |> get(
        summary_path(conn, :show_diagnostic_report, patient_id, UUID.binary_to_string!(diagnostic_report.id.binary))
      )
      |> json_response(200)
      |> Map.take(["data"])
      |> assert_json_schema("diagnostic_reports/diagnostic_report_show.json")
    end

    test "not found when conclusion_code is not allowed", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      diagnostic_report =
        build(
          :diagnostic_report,
          conclusion_code: codeable_concept_coding(system: "eHealth/SNOMED/clinical_findings", code: "111")
        )

      insert(:patient,
        _id: patient_id_hash,
        diagnostic_reports: %{UUID.binary_to_string!(diagnostic_report.id.binary) => diagnostic_report}
      )

      conn
      |> get(
        summary_path(conn, :show_diagnostic_report, patient_id, UUID.binary_to_string!(diagnostic_report.id.binary))
      )
      |> json_response(404)
    end

    test "not found when id is invalid", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      diagnostic_report = build(:diagnostic_report)

      insert(:patient,
        _id: patient_id_hash,
        diagnostic_reports: %{UUID.binary_to_string!(diagnostic_report.id.binary) => diagnostic_report}
      )

      conn
      |> get(summary_path(conn, :show_diagnostic_report, patient_id, UUID.uuid4()))
      |> json_response(404)
    end
  end

  describe "list diagnostic reports" do
    test "successful search", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      resp =
        conn
        |> get(summary_path(conn, :list_diagnostic_reports, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("diagnostic_reports/diagnostic_report_list.json")

      assert %{"page_number" => 1, "total_entries" => 2, "total_pages" => 1} = resp["paging"]
    end

    test "conclusion_code is not allowed", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      diagnostic_report_1 =
        build(:diagnostic_report,
          conclusion_code: codeable_concept_coding(system: "eHealth/SNOMED/clinical_findings", code: "111")
        )

      diagnostic_report_2 = build(:diagnostic_report)

      diagnostic_reports =
        [diagnostic_report_1, diagnostic_report_2]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = diagnostic_report ->
          {UUID.binary_to_string!(id), diagnostic_report}
        end)

      insert(:patient, _id: patient_id_hash, diagnostic_reports: diagnostic_reports)

      resp =
        conn
        |> get(summary_path(conn, :list_diagnostic_reports, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("diagnostic_reports/diagnostic_report_list.json")

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]
    end

    test "invalid search parameters", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      search_params = %{"encounter_id" => UUID.uuid4(), "context_episode_id" => UUID.uuid4()}

      resp =
        conn
        |> get(summary_path(conn, :list_diagnostic_reports, patient_id), search_params)
        |> json_response(422)

      assert [
               %{
                 "entry" => "$.context_episode_id",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               },
               %{
                 "entry" => "$.encounter_id",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               }
             ] = resp["error"]["invalid"]
    end

    test "successful search with search parameters: code", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      service_id = UUID.uuid4()

      code =
        build(:reference,
          identifier:
            build(:identifier,
              type: codeable_concept_coding(code: "service"),
              value: Mongo.string_to_uuid(service_id)
            )
        )

      diagnostic_report_1 = build(:diagnostic_report, code: code)
      diagnostic_report_2 = build(:diagnostic_report)

      diagnostic_reports =
        [diagnostic_report_1, diagnostic_report_2]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = diagnostic_report ->
          {UUID.binary_to_string!(id), diagnostic_report}
        end)

      insert(:patient, _id: patient_id_hash, diagnostic_reports: diagnostic_reports)

      search_params = %{"code" => service_id}

      resp =
        conn
        |> get(summary_path(conn, :list_diagnostic_reports, patient_id), search_params)
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

      search_params = %{"origin_episode_id" => origin_episode_id}

      resp =
        conn
        |> get(summary_path(conn, :list_diagnostic_reports, patient_id), search_params)
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

      call_endpoint = fn search_params ->
        conn
        |> get(summary_path(conn, :list_diagnostic_reports, patient_id), search_params)
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

    test "get patient when diagnostic reports list is null", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, diagnostic_reports: nil)

      resp =
        conn
        |> get(summary_path(conn, :list_diagnostic_reports, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("diagnostic_reports/diagnostic_report_list.json")

      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end
  end

  defp build_condition_code(code) do
    {code, build(:codeable_concept, coding: [build(:coding, code: code, system: "eHealth/ICPC2/condition_codes")])}
  end

  defp get_datetime(day_shift) do
    date = Date.utc_today() |> Date.add(day_shift) |> Date.to_erl()
    {date, {0, 0, 0}} |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
  end

  defp assert_matching_ids(received_ids, db_ids) do
    assert MapSet.new(received_ids) == MapSet.new(db_ids)
  end
end
