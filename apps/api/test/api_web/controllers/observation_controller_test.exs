defmodule Api.Web.ObservationControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase

  import Core.Expectations.CasherExpectation
  import Mox

  alias Core.Observations.Value

  setup %{conn: conn} do
    stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

    {:ok, conn: put_consumer_id_header(conn)}
  end

  describe "get observation" do
    test "success", %{conn: conn} do
      patient = insert(:patient)
      observation = insert(:observation, patient_id: patient._id, value: %Value{type: "period", value: build(:period)})
      expect_get_person_data(patient._id)

      response =
        conn
        |> get(observation_path(conn, :show, patient._id, UUID.binary_to_string!(observation._id.binary)))
        |> json_response(200)

      assert_json_schema(response, "observations/observation_show.json")

      assert %{"start" => _, "end" => _} = response["data"]["value_period"]
    end

    test "not found - invalid patient", %{conn: conn} do
      patient = insert(:patient)
      observation = insert(:observation, patient_id: UUID.uuid4())
      expect_get_person_data(patient._id)

      conn
      |> get(observation_path(conn, :show, patient._id, UUID.binary_to_string!(observation._id.binary)))
      |> json_response(404)
    end

    test "not found - invalid id", %{conn: conn} do
      patient = insert(:patient)
      insert(:observation, patient_id: UUID.uuid4())

      expect_get_person_data(patient._id)

      conn
      |> get(observation_path(conn, :show, patient._id, UUID.uuid4()))
      |> json_response(404)
    end
  end

  describe "search observations" do
    test "success by code, encounter_id, episode_id, issued_from, issued_to", %{conn: conn} do
      episode = build(:episode)
      episode2 = build(:episode)

      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))
      encounter2 = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode2.id)))

      patient =
        insert(
          :patient,
          episodes: %{
            UUID.binary_to_string!(episode.id.binary) => episode,
            UUID.binary_to_string!(episode2.id.binary) => episode2
          },
          encounters: %{
            UUID.binary_to_string!(encounter.id.binary) => encounter,
            UUID.binary_to_string!(encounter2.id.binary) => encounter2
          }
        )

      expect_get_person_data(patient._id)
      {code, observation_code} = build_observation_code()
      context = build(:reference, identifier: build(:identifier, value: encounter.id))

      {_, issued, _} = DateTime.from_iso8601("1991-01-01 00:00:00Z")
      {_, issued2, _} = DateTime.from_iso8601("2010-01-01 00:00:00Z")

      insert(:observation, patient_id: patient._id, context: context, code: observation_code, issued: issued)
      insert(:observation, patient_id: patient._id, context: context, code: observation_code, issued: issued)

      # Next observations have no correct code, encounter, patient_id, issued
      insert(:observation, patient_id: patient._id, context: context, code: observation_code, issued: issued2)
      insert(:observation, patient_id: patient._id, context: context)
      insert(:observation, context: context)
      insert(:observation)

      request_params = %{
        "code" => code,
        "encounter_id" => UUID.binary_to_string!(encounter.id.binary),
        "episode_id" => UUID.binary_to_string!(episode.id.binary),
        "issued_from" => "1980-01-01",
        "issued_to" => "2000-01-01"
      }

      response =
        conn
        |> get(observation_path(conn, :index, patient._id), request_params)
        |> json_response(200)

      assert 2 == response["paging"]["total_entries"]
    end

    test "success by issued_from, issued_to", %{conn: conn} do
      patient = insert(:patient)
      expect_get_person_data(patient._id, 8)
      create_date = &(DateTime.from_iso8601("#{&1} 00:00:00Z") |> elem(1))

      insert_list(10, :observation, patient_id: patient._id, issued: create_date.("1990-01-01"))
      insert_list(10, :observation, patient_id: patient._id, issued: create_date.("2000-01-01"))
      insert_list(10, :observation, patient_id: patient._id, issued: create_date.("2010-01-01"))
      insert_list(10, :observation, patient_id: patient._id, issued: DateTime.utc_now())

      call_endpoint = fn request_params ->
        conn
        |> get(observation_path(conn, :index, patient._id), request_params)
        |> json_response(200)
        |> Map.get("data")
        |> length()
      end

      today_date = to_string(Date.utc_today())

      assert 0 = call_endpoint.(%{"issued_to" => "1989-01-01"})
      assert 0 = call_endpoint.(%{"issued_from" => "2001-01-01", "issued_to" => "2005-01-01"})
      assert 0 = call_endpoint.(%{"issued_from" => "3001-01-01"})

      assert 10 = call_endpoint.(%{"issued_from" => "1980-01-01", "issued_to" => "1999-01-01"})
      assert 20 = call_endpoint.(%{"issued_from" => "1980-01-01", "issued_to" => "2005-01-01"})
      assert 20 = call_endpoint.(%{"issued_from" => "2010-01-01", "issued_to" => today_date})
      assert 40 = call_endpoint.(%{"issued_from" => "1990-01-01"})
      assert 40 = call_endpoint.(%{"issued_from" => "1990-01-01", "issued_to" => today_date})
    end

    test "success by code", %{conn: conn} do
      patient = insert(:patient)
      expect_get_person_data(patient._id)
      {code, observation_code} = build_observation_code()

      insert(:observation, patient_id: patient._id, code: observation_code)
      insert(:observation, patient_id: patient._id, code: observation_code)

      # Next observations have no correct code, patient_id
      insert(:observation, patient_id: patient._id)
      insert(:observation)

      request_params = %{"code" => code}

      response =
        conn
        |> get(observation_path(conn, :index, patient._id), request_params)
        |> json_response(200)

      assert_json_schema(response, "observations/observations_list.json")

      assert 2 == response["paging"]["total_entries"]

      Enum.each(response["data"], fn %{"code" => %{"coding" => [%{"code" => entity_code}]}} ->
        assert entity_code == code
      end)
    end

    test "success by encounter_id", %{conn: conn} do
      encounter = build(:encounter)
      encounter_id = UUID.binary_to_string!(encounter.id.binary)
      patient = insert(:patient, encounters: %{encounter_id => encounter})
      context = build_encounter_context(encounter.id)
      expect_get_person_data(patient._id)

      insert_list(3, :observation, patient_id: patient._id, context: context)

      # Next observations have no encounter_id
      insert_list(2, :observation, patient_id: patient._id)

      request_params = %{
        "encounter_id" => encounter_id
      }

      response =
        conn
        |> get(observation_path(conn, :index, patient._id), request_params)
        |> json_response(200)

      assert 3 == get_in(response, ["paging", "total_entries"])

      Enum.each(response["data"], fn %{"context" => %{"identifier" => %{"value" => entity_encounter_id}}} ->
        assert entity_encounter_id == encounter_id
      end)
    end

    test "success by episode_id, encounter_id", %{conn: conn} do
      episode = build(:episode)
      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))
      encounter2 = build(:encounter)
      context = build_encounter_context(encounter.id)
      context2 = build_encounter_context(encounter2.id)

      patient =
        insert(:patient,
          episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
          encounters: %{
            UUID.binary_to_string!(encounter.id.binary) => encounter,
            UUID.binary_to_string!(encounter2.id.binary) => encounter2
          }
        )

      expect_get_person_data(patient._id)
      insert_list(3, :observation, patient_id: patient._id, context: context)

      # Next observations have no episode_id
      insert_list(10, :observation, patient_id: patient._id, context: context2)

      request_params = %{
        "episode_id" => UUID.binary_to_string!(episode.id.binary)
      }

      response =
        conn
        |> get(observation_path(conn, :index, patient._id), request_params)
        |> json_response(200)

      assert 3 == get_in(response, ["paging", "total_entries"])
    end

    test "success by patient_id with pagination", %{conn: conn} do
      patient = insert(:patient)
      expect_get_person_data(patient._id, 2)
      insert_list(11, :observation, patient_id: patient._id)
      # defaults: paging = 50, page = 1
      assert %{
               "page_number" => 1,
               "page_size" => 50,
               "total_entries" => 11,
               "total_pages" => 1
             } ==
               conn
               |> get(observation_path(conn, :index, patient._id), %{})
               |> json_response(200)
               |> Map.get("paging")

      response =
        conn
        |> get(observation_path(conn, :index, patient._id), %{"page" => "2", "page_size" => "5"})
        |> json_response(200)

      assert %{"page_size" => 5, "page_number" => 2, "total_pages" => 3} = response["paging"]
      assert 5 == length(response["data"])
    end

    test "empty results", %{conn: conn} do
      patient = insert(:patient)
      expect_get_person_data(patient._id)
      insert(:observation)

      assert [] =
               conn
               |> get(observation_path(conn, :index, patient._id), %{})
               |> json_response(200)
               |> get_in(["data"])
    end
  end

  defp build_observation_code do
    code = "#{Enum.random(10_000..99_999)}-2"
    observation_code = codeable_concept_coding(code: code, system: "eHealth/observations_codes")
    {code, observation_code}
  end

  defp build_encounter_context(%BSON.Binary{} = encounter_id) do
    build(:reference, identifier: build(:identifier, value: encounter_id))
  end
end
