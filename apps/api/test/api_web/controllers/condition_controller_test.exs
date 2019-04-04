defmodule Api.Web.ConditionControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase

  import Core.Expectations.CasherExpectation
  import Mox

  alias Core.Patients

  setup %{conn: conn} do
    stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

    {:ok, conn: put_consumer_id_header(conn)}
  end

  describe "search conditions" do
    test "success by code, encounter_id, episode_id, onset_date", %{conn: conn} do
      episode = build(:episode)
      episode2 = build(:episode)

      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))
      encounter2 = build(:encounter)

      encounter_id = UUID.binary_to_string!(encounter.id.binary)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{
          UUID.binary_to_string!(episode.id.binary) => episode,
          UUID.binary_to_string!(episode2.id.binary) => episode2
        },
        encounters: %{
          UUID.binary_to_string!(encounter.id.binary) => encounter,
          UUID.binary_to_string!(encounter2.id.binary) => encounter2
        }
      )

      expect_get_person_data(patient_id)

      {code, condition_code} = build_condition_code()

      {_, onset_date, _} = DateTime.from_iso8601("1991-01-01 00:00:00Z")
      {_, onset_date2, _} = DateTime.from_iso8601("2010-01-01 00:00:00Z")

      insert_list(
        2,
        :condition,
        patient_id: patient_id_hash,
        encounter_context: encounter,
        code: condition_code,
        asserted_date: nil,
        onset_date: onset_date
      )

      # Missed code, encounter, patient_id
      insert(:condition,
        patient_id: patient_id_hash,
        encounter_context: encounter,
        onset_date: onset_date2
      )

      insert(:condition, patient_id: patient_id_hash, encounter_context: encounter)
      insert(:condition, patient_id: patient_id_hash)
      insert(:condition)

      request_params = %{
        "code" => code,
        "encounter_id" => encounter_id,
        "episode_id" => UUID.binary_to_string!(episode.id.binary),
        "onset_date_from" => "1990-01-01",
        "onset_date_to" => "2000-01-01"
      }

      response =
        conn
        |> get(condition_path(conn, :index, patient_id), request_params)
        |> json_response(200)
        |> assert_json_schema("conditions/conditions_list.json")

      Enum.each(response["data"], fn condition ->
        assert %{"context" => %{"identifier" => %{"value" => ^encounter_id}}} = condition
        assert %{"code" => %{"coding" => [%{"code" => ^code}]}} = condition
      end)

      assert 2 == response["paging"]["total_entries"]
    end

    test "success by onset_date_from, onset_date_to", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      expect_get_person_data(patient_id, 8)
      create_date = &(DateTime.from_iso8601("#{&1} 00:00:00Z") |> elem(1))

      insert_list(10, :condition, patient_id: patient_id_hash, onset_date: create_date.("1990-01-01"))
      insert_list(10, :condition, patient_id: patient_id_hash, onset_date: create_date.("2000-01-01"))
      insert_list(10, :condition, patient_id: patient_id_hash, onset_date: create_date.("2010-01-01"))
      insert_list(10, :condition, patient_id: patient_id_hash, onset_date: DateTime.utc_now())

      call_endpoint = fn request_params ->
        conn
        |> get(condition_path(conn, :index, patient_id), request_params)
        |> json_response(200)
        |> Map.get("data")
        |> length()
      end

      today_date = to_string(Date.utc_today())

      assert 0 == call_endpoint.(%{"onset_date_to" => "1989-01-01"})
      assert 0 == call_endpoint.(%{"onset_date_from" => "2001-01-01", "onset_date_to" => "2005-01-01"})
      assert 0 == call_endpoint.(%{"onset_date_from" => "3001-01-01"})

      assert 10 == call_endpoint.(%{"onset_date_from" => "1980-01-01", "onset_date_to" => "1999-01-01"})
      assert 20 == call_endpoint.(%{"onset_date_from" => "1980-01-01", "onset_date_to" => "2005-01-01"})
      assert 20 == call_endpoint.(%{"onset_date_from" => "2010-01-01", "onset_date_to" => today_date})
      assert 40 == call_endpoint.(%{"onset_date_from" => "1990-01-01"})
      assert 40 == call_endpoint.(%{"onset_date_from" => "1990-01-01", "onset_date_to" => today_date})
    end

    test "success by code", %{conn: conn} do
      episode = build(:episode)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, episodes: %{to_string(episode.id) => episode}, _id: patient_id_hash)
      expect_get_person_data(patient_id)
      {code, condition_code} = build_condition_code()

      insert_list(2, :condition, patient_id: patient_id_hash, code: condition_code)

      # Missed code, patient_id
      insert(:condition, patient_id: patient_id_hash)
      insert(:condition)

      request_params = %{"code" => code}

      response =
        conn
        |> get(condition_path(conn, :index, patient_id), request_params)
        |> json_response(200)

      assert 2 == response["paging"]["total_entries"]

      Enum.each(response["data"], fn %{"code" => %{"coding" => [%{"code" => entity_code}]}} ->
        assert entity_code == code
      end)
    end

    test "success by encounter_id and episode_id", %{conn: conn} do
      episode = build(:episode)

      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))
      encounter2 = build(:encounter)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        encounters: %{
          UUID.binary_to_string!(encounter.id.binary) => encounter,
          UUID.binary_to_string!(encounter2.id.binary) => encounter2
        }
      )

      expect_get_person_data(patient_id)

      insert_list(4, :condition, patient_id: patient_id_hash, encounter_context: encounter)

      # Missed encounter, episode_id
      insert_list(5, :condition, patient_id: patient_id_hash)
      insert_list(5, :condition)

      request_params = %{
        "episode_id" => UUID.binary_to_string!(episode.id.binary),
        "encounter_id" => UUID.binary_to_string!(encounter.id.binary)
      }

      response =
        conn
        |> get(condition_path(conn, :index, patient_id), request_params)
        |> json_response(200)

      assert 4 == get_in(response, ["paging", "total_entries"])

      Enum.each(response["data"], fn %{"context" => %{"identifier" => %{"value" => entity_encounter_id}}} ->
        assert entity_encounter_id == UUID.binary_to_string!(encounter.id.binary)
      end)
    end

    test "success by episode context", %{conn: conn} do
      episode = build(:episode)

      encounter1 = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))
      encounter2 = build(:encounter)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{to_string(episode.id) => episode},
        encounters: %{
          to_string(encounter1.id) => encounter1,
          to_string(encounter2.id) => encounter2
        }
      )

      expect_get_person_data(patient_id)

      insert_list(4, :condition, patient_id: patient_id_hash, encounter_context: encounter1)

      # Missed encounter, episode_id
      insert_list(5, :condition, patient_id: patient_id_hash)
      insert_list(5, :condition)

      response =
        conn
        |> get(episode_context_condition_path(conn, :index, patient_id, to_string(encounter1.episode.identifier.value)))
        |> json_response(200)

      assert 4 == get_in(response, ["paging", "total_entries"])

      Enum.each(response["data"], fn %{"context" => %{"identifier" => %{"value" => entity_encounter_id}}} ->
        assert entity_encounter_id == to_string(encounter1.id)
      end)
    end

    test "success by encounter_id with pagination", %{conn: conn} do
      encounter = build(:encounter)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter}, _id: patient_id_hash)
      expect_get_person_data(patient_id, 2)

      insert_list(11, :condition, patient_id: patient_id_hash, encounter_context: encounter)

      # Missed context
      insert_list(2, :condition, patient_id: patient_id_hash)
      insert_list(3, :condition)

      request_params = %{
        "encounter_id" => UUID.binary_to_string!(encounter.id.binary)
      }

      response =
        conn
        |> get(condition_path(conn, :index, patient_id), request_params)
        |> json_response(200)

      # defaults: paging = 50, page = 1
      assert %{
               "page_number" => 1,
               "page_size" => 50,
               "total_entries" => 11,
               "total_pages" => 1
             } = response["paging"]

      response =
        conn
        |> get(condition_path(conn, :index, patient_id), %{"page" => "2", "page_size" => "5"})
        |> json_response(200)

      assert %{"page_size" => 5, "page_number" => 2, "total_pages" => 3} = response["paging"]
      assert 5 == length(response["data"])
    end

    test "empty results", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      expect_get_person_data(patient_id)

      insert(:condition)

      assert [] =
               conn
               |> get(condition_path(conn, :index, patient_id), %{})
               |> json_response(200)
               |> get_in(["data"])
    end

    test "empty result on invalid episode id", %{conn: conn} do
      episode = build(:episode)
      encounter = build(:encounter)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      expect_get_person_data(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter}
      )

      insert_list(3, :condition, patient_id: patient_id_hash, encounter_context: encounter)

      request_data = %{
        "episode_id" => UUID.binary_to_string!(episode.id.binary)
      }

      assert [] ==
               conn
               |> get(condition_path(conn, :index, patient_id), request_data)
               |> json_response(200)
               |> Map.get("data")
    end

    test "invalid search parameters", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      expect_get_person_data(patient_id)
      insert(:patient, _id: patient_id_hash)
      search_params = %{"onset_date_from" => "invalid"}

      resp =
        conn
        |> get(condition_path(conn, :index, patient_id), search_params)
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
      condition = insert(:condition, patient_id: patient_id_hash, asserted_date: nil)

      expect_get_person_data(patient_id)

      conn
      |> get(condition_path(conn, :show, patient_id, UUID.binary_to_string!(condition._id.binary)))
      |> json_response(200)
      |> assert_json_schema("conditions/condition_show.json")
    end

    test "condition not found", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      expect_get_person_data(patient_id)

      conn
      |> get(condition_path(conn, :show, patient_id, UUID.uuid4()))
      |> json_response(404)
    end

    test "success by episode context", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      episode = build(:episode)
      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))

      insert(
        :patient,
        _id: patient_id_hash,
        encounters: %{
          to_string(encounter.id) => encounter
        },
        episodes: %{
          to_string(episode.id) => episode
        }
      )

      condition = insert(:condition, patient_id: patient_id_hash, encounter_context: encounter, asserted_date: nil)

      expect_get_person_data(patient_id)

      conn
      |> get(
        episode_context_condition_path(
          conn,
          :show_by_episode,
          patient_id,
          to_string(episode.id),
          to_string(condition._id)
        )
      )
      |> json_response(200)
      |> assert_json_schema("conditions/condition_show.json")
    end

    test "not found by episode context", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      episode = build(:episode)
      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))

      insert(
        :patient,
        _id: patient_id_hash,
        encounters: %{
          to_string(encounter.id) => encounter
        },
        episodes: %{
          to_string(episode.id) => episode
        }
      )

      condition = insert(:condition, patient_id: patient_id_hash, encounter_context: encounter, asserted_date: nil)

      expect_get_person_data(patient_id)

      assert conn
             |> get(
               episode_context_condition_path(
                 conn,
                 :show_by_episode,
                 patient_id,
                 UUID.uuid4(),
                 to_string(condition._id)
               )
             )
             |> json_response(404)
    end
  end

  defp build_condition_code do
    code = "J11"

    condition_code =
      build(:codeable_concept, coding: [build(:coding, code: code, system: "eHealth/ICD10/condition_codes")])

    {code, condition_code}
  end
end
