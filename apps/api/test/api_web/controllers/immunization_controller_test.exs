defmodule Api.Web.ImmunizationControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase

  import Core.Expectations.CasherExpectation
  import Mox

  alias Core.Patients

  describe "show immunization" do
    test "successful show", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      immunization_in = build(:immunization)
      immunization_out = build(:immunization)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        immunizations: %{
          UUID.binary_to_string!(immunization_in.id.binary) => immunization_in,
          UUID.binary_to_string!(immunization_out.id.binary) => immunization_out
        }
      )

      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(immunization_path(conn, :show, patient_id, UUID.binary_to_string!(immunization_in.id.binary)))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("immunizations/immunization_show.json")

      assert get_in(resp, ~w(data id)) == UUID.binary_to_string!(immunization_in.id.binary)
      refute get_in(resp, ~w(data id)) == UUID.binary_to_string!(immunization_out.id.binary)
    end

    test "invalid patient uuid", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      expect_get_person_data_empty()

      conn
      |> get(immunization_path(conn, :show, UUID.uuid4(), UUID.uuid4()))
      |> json_response(401)
    end

    test "invalid immunization uuid", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      immunization = build(:immunization)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        immunizations: %{UUID.binary_to_string!(immunization.id.binary) => immunization}
      )

      expect_get_person_data(patient_id)

      conn
      |> get(immunization_path(conn, :show, patient_id, UUID.uuid4()))
      |> json_response(404)
    end

    test "get patient when no immunizations", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, immunizations: %{})
      expect_get_person_data(patient_id)

      conn
      |> get(immunization_path(conn, :show, patient_id, UUID.uuid4()))
      |> json_response(404)
    end
  end

  describe "index immunization" do
    test "successful search", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(immunization_path(conn, :index, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("immunizations/immunization_list.json")

      assert %{"page_number" => 1, "total_entries" => 2, "total_pages" => 1} = resp["paging"]
    end

    test "successful search with search parameters: encounter_id", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      encounter_id = UUID.uuid4()
      context = build_encounter_context(Mongo.string_to_uuid(encounter_id))
      immunization_in = build(:immunization, context: context)
      immunization_out = build(:immunization)

      immunizations =
        [immunization_in, immunization_out]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = immunization ->
          {UUID.binary_to_string!(id), immunization}
        end)

      insert(:patient, _id: patient_id_hash, immunizations: immunizations)
      expect_get_person_data(patient_id)

      search_params = %{"encounter_id" => encounter_id}

      resp =
        conn
        |> get(immunization_path(conn, :index, patient_id), search_params)
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("immunizations/immunization_list.json")

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      resp =
        resp
        |> Map.get("data")
        |> hd()

      refute Map.get(resp, "id") == UUID.binary_to_string!(immunization_out.id.binary)
      assert Map.get(resp, "id") == UUID.binary_to_string!(immunization_in.id.binary)
      assert get_in(resp, ~w(context identifier value)) == encounter_id
    end

    test "successful search with search parameters: vaccine_code", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      code = "wex-10"

      vaccine_code =
        build(
          :codeable_concept,
          coding: [
            build(:coding, code: code, system: "eHealth/vaccines_codes"),
            build(:coding, code: "test", system: "eHealth/vaccines_codes")
          ]
        )

      immunization_in = build(:immunization, vaccine_code: vaccine_code)
      immunization_out = build(:immunization)

      immunizations =
        [immunization_in, immunization_out]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = immunization ->
          {UUID.binary_to_string!(id), immunization}
        end)

      insert(:patient, _id: patient_id_hash, immunizations: immunizations)
      expect_get_person_data(patient_id)

      search_params = %{"vaccine_code" => code}

      resp =
        conn
        |> get(immunization_path(conn, :index, patient_id), search_params)
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("immunizations/immunization_list.json")

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]
    end

    test "successful search with search parameters: episode_id", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      episode_in = build(:episode)
      episode_out = build(:episode)

      encounter_in = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode_in.id)))
      encounter_out = build(:encounter)

      encounter_id = UUID.binary_to_string!(encounter_in.id.binary)
      context = build_encounter_context(Mongo.string_to_uuid(encounter_id))
      immunization_in = build(:immunization, context: context)
      immunization_out = build(:immunization)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{
          UUID.binary_to_string!(episode_in.id.binary) => episode_in,
          UUID.binary_to_string!(episode_out.id.binary) => episode_out
        },
        encounters: %{
          UUID.binary_to_string!(encounter_in.id.binary) => encounter_in,
          UUID.binary_to_string!(encounter_out.id.binary) => encounter_out
        },
        immunizations: %{
          UUID.binary_to_string!(immunization_in.id.binary) => immunization_in,
          UUID.binary_to_string!(immunization_out.id.binary) => immunization_out
        }
      )

      expect_get_person_data(patient_id)

      search_params = %{"episode_id" => UUID.binary_to_string!(episode_in.id.binary)}

      resp =
        conn
        |> get(immunization_path(conn, :index, patient_id), search_params)
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("immunizations/immunization_list.json")

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]
    end

    test "successful search with search parameters: date", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

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
      expect_get_person_data(patient_id, 4)

      call_endpoint = fn search_params ->
        conn
        |> get(immunization_path(conn, :index, patient_id), search_params)
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

    test "successful search with search parameters: complex test", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      code = "wex-10"

      vaccine_code =
        build(
          :codeable_concept,
          coding: [
            build(:coding, code: code, system: "eHealth/vaccines_codes"),
            build(:coding, code: "test", system: "eHealth/vaccines_codes")
          ]
        )

      date_from = Date.utc_today() |> Date.add(-20) |> Date.to_iso8601()
      date_to = Date.utc_today() |> Date.add(-10) |> Date.to_iso8601()

      encounter_id_1 = UUID.uuid4()
      context_encounter_id = build_encounter_context(Mongo.string_to_uuid(encounter_id_1))

      episode = build(:episode)
      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))
      encounter_id_2 = UUID.binary_to_string!(encounter.id.binary)
      context_episode_id = build_encounter_context(Mongo.string_to_uuid(encounter_id_2))

      immunization_in_1 =
        build(:immunization, context: context_encounter_id, vaccine_code: vaccine_code, date: get_datetime(-15))

      immunization_out_1 = build(:immunization, context: context_encounter_id, date: get_datetime(-15))
      immunization_out_2 = build(:immunization, vaccine_code: vaccine_code, date: get_datetime(-15))

      immunization_in_2 =
        build(:immunization, context: context_episode_id, vaccine_code: vaccine_code, date: get_datetime(-15))

      immunization_out_3 = build(:immunization, date: get_datetime(-30))
      immunization_out_4 = build(:immunization, date: get_datetime(-15))
      immunization_out_5 = build(:immunization, date: get_datetime(-5))

      immunizations =
        [
          immunization_in_1,
          immunization_in_2,
          immunization_out_1,
          immunization_out_2,
          immunization_out_3,
          immunization_out_4,
          immunization_out_5
        ]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = immunization ->
          {UUID.binary_to_string!(id), immunization}
        end)

      insert(
        :patient,
        _id: patient_id_hash,
        immunizations: immunizations,
        episodes: %{
          UUID.binary_to_string!(episode.id.binary) => episode
        },
        encounters: %{
          UUID.binary_to_string!(encounter.id.binary) => encounter
        }
      )

      expect_get_person_data(patient_id, 3)

      search_params = %{
        "encounter_id" => encounter_id_1,
        "vaccine_code" => code,
        "episode_id" => UUID.binary_to_string!(episode.id.binary),
        "date_from" => date_from,
        "date_to" => date_to
      }

      call_endpoint = fn search_params ->
        conn
        |> get(immunization_path(conn, :index, patient_id), search_params)
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

      assert Map.get(resp, "id") == UUID.binary_to_string!(immunization_in_2.id.binary)
      assert get_in(resp, ~w(context identifier value)) == encounter_id_2

      # all params except episode_id
      resp = call_endpoint.(Map.delete(search_params, "episode_id"))

      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      resp =
        resp
        |> Map.get("data")
        |> hd()

      assert Map.get(resp, "id") == UUID.binary_to_string!(immunization_in_1.id.binary)
      assert get_in(resp, ~w(context identifier value)) == encounter_id_1
    end

    test "get patient when no immunizations", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, immunizations: %{})
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(immunization_path(conn, :index, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("immunizations/immunization_list.json")

      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end

    test "get patient when immunizations list is null", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, immunizations: nil)
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(immunization_path(conn, :index, patient_id))
        |> json_response(200)

      resp
      |> Map.take(["data"])
      |> assert_json_schema("immunizations/immunization_list.json")

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
