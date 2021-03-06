defmodule Api.Web.ObservationControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase
  alias Core.Observations.Value
  alias Core.Patients

  setup %{conn: conn} do
    {:ok, conn: put_consumer_id_header(conn)}
  end

  describe "get observation" do
    test "success", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)
      observation = insert(:observation, patient_id: patient_id_hash, value: %Value{value_period: build(:period)})

      response_data =
        conn
        |> get(observation_path(conn, :show, patient_id, UUID.binary_to_string!(observation._id.binary)))
        |> json_response(200)
        |> Map.get("data")
        |> assert_json_schema("observations/observation_show.json")

      assert %{"start" => _, "end" => _} = response_data["value_period"]
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

      observation =
        insert(:observation,
          patient_id: patient_id_hash,
          value: %Value{value_period: build(:period)},
          encounter_context: encounter
        )

      response_data =
        conn
        |> get(
          episode_context_observation_path(
            conn,
            :show_by_episode,
            patient_id,
            to_string(episode.id),
            to_string(observation._id)
          )
        )
        |> json_response(200)
        |> Map.get("data")
        |> assert_json_schema("observations/observation_show.json")

      assert %{"start" => _, "end" => _} = response_data["value_period"]
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

      observation =
        insert(:observation,
          patient_id: patient_id_hash,
          value: %Value{value_period: build(:period)},
          encounter_context: encounter
        )

      assert conn
             |> get(
               episode_context_observation_path(
                 conn,
                 :show_by_episode,
                 patient_id,
                 UUID.uuid4(),
                 to_string(observation._id)
               )
             )
             |> json_response(404)
    end

    test "not found - invalid patient", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      observation = insert(:observation, patient_id: Patients.get_pk_hash(UUID.uuid4()))

      conn
      |> get(observation_path(conn, :show, patient_id, UUID.binary_to_string!(observation._id.binary)))
      |> json_response(404)
    end

    test "not found - invalid id", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      insert(:observation, patient_id: patient_id_hash)

      conn
      |> get(observation_path(conn, :show, patient_id, UUID.uuid4()))
      |> json_response(404)
    end
  end

  describe "search observations" do
    test "success by code, encounter_id, episode_id, issued_from, issued_to, diagnostic_report_id", %{conn: conn} do
      episode = build(:episode)
      episode2 = build(:episode)

      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))
      encounter2 = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode2.id)))

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      diagnostic_report_id = UUID.uuid4()

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

      {code, observation_code} = build_observation_code()

      {_, issued, _} = DateTime.from_iso8601("1991-01-01 00:00:00Z")
      {_, issued2, _} = DateTime.from_iso8601("2010-01-01 00:00:00Z")

      insert(:observation,
        patient_id: patient_id_hash,
        encounter_context: encounter,
        code: observation_code,
        issued: issued,
        diagnostic_report:
          build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(diagnostic_report_id)))
      )

      insert(:observation,
        patient_id: patient_id_hash,
        encounter_context: encounter,
        code: observation_code,
        issued: issued,
        diagnostic_report:
          build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(diagnostic_report_id)))
      )

      # Next observations have no correct code, encounter, patient_id, issued, diagnostic_report_id
      insert(:observation,
        patient_id: patient_id_hash,
        encounter_context: encounter,
        code: observation_code,
        issued: issued2,
        diagnostic_report: build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(UUID.uuid4())))
      )

      insert(:observation, patient_id: patient_id_hash, encounter_context: encounter)
      insert(:observation, encounter_context: encounter)
      insert(:observation)

      request_params = %{
        "code" => code,
        "encounter_id" => UUID.binary_to_string!(encounter.id.binary),
        "episode_id" => UUID.binary_to_string!(episode.id.binary),
        "issued_from" => "1980-01-01",
        "issued_to" => "2000-01-01",
        "diagnostic_report_id" => diagnostic_report_id
      }

      response =
        conn
        |> get(observation_path(conn, :index, patient_id), request_params)
        |> json_response(200)

      assert 2 == response["paging"]["total_entries"]
    end

    test "success by issued_from, issued_to", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      create_date = &(DateTime.from_iso8601("#{&1} 00:00:00Z") |> elem(1))

      insert_list(10, :observation, patient_id: patient_id_hash, issued: create_date.("1990-01-01"))
      insert_list(10, :observation, patient_id: patient_id_hash, issued: create_date.("2000-01-01"))
      insert_list(10, :observation, patient_id: patient_id_hash, issued: create_date.("2010-01-01"))
      insert_list(10, :observation, patient_id: patient_id_hash, issued: DateTime.utc_now())

      call_endpoint = fn request_params ->
        conn
        |> get(observation_path(conn, :index, patient_id), request_params)
        |> json_response(200)
        |> Map.get("data")
        |> length()
      end

      today_date = to_string(Date.utc_today())

      assert 0 == call_endpoint.(%{"issued_to" => "1989-01-01"})
      assert 0 == call_endpoint.(%{"issued_from" => "2001-01-01", "issued_to" => "2005-01-01"})
      assert 0 == call_endpoint.(%{"issued_from" => "3001-01-01"})

      assert 10 == call_endpoint.(%{"issued_from" => "1980-01-01", "issued_to" => "1999-01-01"})
      assert 20 == call_endpoint.(%{"issued_from" => "1980-01-01", "issued_to" => "2005-01-01"})
      assert 20 == call_endpoint.(%{"issued_from" => "2010-01-01", "issued_to" => today_date})
      assert 40 == call_endpoint.(%{"issued_from" => "1990-01-01"})
      assert 40 == call_endpoint.(%{"issued_from" => "1990-01-01", "issued_to" => today_date})
    end

    test "success by code", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      {code, observation_code} = build_observation_code()

      insert(:observation, patient_id: patient_id_hash, code: observation_code)
      insert(:observation, patient_id: patient_id_hash, code: observation_code)

      # Next observations have no correct code, patient_id
      insert(:observation, patient_id: patient_id_hash)
      insert(:observation)

      request_params = %{"code" => code}

      response =
        conn
        |> get(observation_path(conn, :index, patient_id), request_params)
        |> json_response(200)

      assert_json_schema(response["data"], "observations/observations_list.json")

      assert 2 == response["paging"]["total_entries"]

      Enum.each(response["data"], fn %{"code" => %{"coding" => [%{"code" => entity_code}]}} ->
        assert entity_code == code
      end)
    end

    test "success by encounter_id", %{conn: conn} do
      encounter = build(:encounter)
      encounter_id = UUID.binary_to_string!(encounter.id.binary)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, encounters: %{encounter_id => encounter}, _id: patient_id_hash)

      insert_list(3, :observation,
        patient_id: patient_id_hash,
        encounter_context: encounter
      )

      # Next observations have no encounter_id
      insert_list(2, :observation, patient_id: patient_id_hash)

      request_params = %{
        "encounter_id" => encounter_id
      }

      response =
        conn
        |> get(observation_path(conn, :index, patient_id), request_params)
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

      insert_list(3, :observation,
        patient_id: patient_id_hash,
        encounter_context: encounter
      )

      # Next observations have no episode_id
      insert_list(10, :observation, patient_id: patient_id_hash, encounter_context: encounter2)

      request_params = %{
        "episode_id" => UUID.binary_to_string!(episode.id.binary)
      }

      response =
        conn
        |> get(observation_path(conn, :index, patient_id), request_params)
        |> json_response(200)

      assert 3 == get_in(response, ["paging", "total_entries"])
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

      insert_list(3, :observation, patient_id: patient_id_hash, encounter_context: encounter1)

      # Next observations have no episode_id
      insert_list(10, :observation, patient_id: patient_id_hash, encounter_context: encounter2)

      response =
        conn
        |> get(episode_context_observation_path(conn, :index, patient_id, to_string(episode.id)))
        |> json_response(200)

      assert 3 == get_in(response, ["paging", "total_entries"])
    end

    test "success by diagnostic_report_id", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      diagnostic_report_id = UUID.uuid4()

      insert_list(3, :observation,
        patient_id: patient_id_hash,
        diagnostic_report:
          build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(diagnostic_report_id)))
      )

      insert_list(10, :observation,
        patient_id: patient_id_hash,
        diagnostic_report: build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(UUID.uuid4())))
      )

      request_params = %{
        "diagnostic_report_id" => diagnostic_report_id
      }

      response =
        conn
        |> get(observation_path(conn, :index, patient_id), request_params)
        |> json_response(200)

      assert 3 == get_in(response, ["paging", "total_entries"])
    end

    test "success by patient_id with pagination", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      insert_list(11, :observation, patient_id: patient_id_hash)
      # defaults: paging = 50, page = 1
      assert %{
               "page_number" => 1,
               "page_size" => 50,
               "total_entries" => 11,
               "total_pages" => 1
             } ==
               conn
               |> get(observation_path(conn, :index, patient_id), %{})
               |> json_response(200)
               |> Map.get("paging")

      response =
        conn
        |> get(observation_path(conn, :index, patient_id), %{"page" => "2", "page_size" => "5"})
        |> json_response(200)

      assert %{"page_size" => 5, "page_number" => 2, "total_pages" => 3} = response["paging"]
      assert 5 == length(response["data"])
    end

    test "empty result on invalid episode id", %{conn: conn} do
      episode = build(:episode)
      encounter = build(:encounter)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter}
      )

      insert_list(3, :observation, patient_id: patient_id_hash, encounter_context: encounter)

      request_data = %{
        "episode_id" => UUID.binary_to_string!(episode.id.binary)
      }

      assert conn
             |> get(observation_path(conn, :index, patient_id), request_data)
             |> json_response(200)
             |> Map.get("data")
             |> Kernel.==([])
    end

    test "empty results", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      insert(:observation)

      assert [] =
               conn
               |> get(observation_path(conn, :index, patient_id), %{})
               |> json_response(200)
               |> get_in(["data"])
    end

    test "invalid search parameters", %{conn: conn} do
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      search_params = %{"issued_from" => "invalid"}

      resp =
        conn
        |> get(observation_path(conn, :index, patient_id), search_params)
        |> json_response(422)

      assert [
               %{
                 "entry" => "$.issued_from",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"rule" => "date"}]
               }
             ] = resp["error"]["invalid"]
    end
  end

  defp build_observation_code do
    code = "1"
    observation_code = codeable_concept_coding(code: code, system: "eHealth/LOINC/observation_codes")
    {code, observation_code}
  end
end
