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

      observation =
        insert(:observation, patient_id: patient._id, value: %Value{type: "value_period", value: build(:period)})

      expect_get_person_data(patient._id)

      response =
        conn
        |> get(observation_path(conn, :show, patient._id, observation._id))
        |> json_response(200)

      assert_json_schema(response, "observations/observation_show.json")

      assert %{"start" => _, "end" => _} = response["data"]["value_period"]
    end

    test "not found - invalid patient", %{conn: conn} do
      patient = insert(:patient)
      observation = insert(:observation, patient_id: UUID.uuid4())
      expect_get_person_data(patient._id)

      conn
      |> get(observation_path(conn, :show, patient._id, observation._id))
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
    test "success by code, encounter_id, episode_id", %{conn: conn} do
      episode = build(:episode)
      episode2 = build(:episode)

      encounter = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode.id)))
      encounter2 = build(:encounter, episode: build(:reference, identifier: build(:identifier, value: episode2.id)))

      patient =
        insert(
          :patient,
          episodes: %{episode.id => episode, episode2.id => episode2},
          encounters: %{encounter.id => encounter, encounter2.id => encounter2}
        )

      expect_get_person_data(patient._id)
      {code, observation_code} = build_observation_code()
      context = build(:reference, identifier: build(:identifier, value: encounter.id))

      insert(:observation, patient_id: patient._id, context: context, code: observation_code)
      insert(:observation, patient_id: patient._id, context: context, code: observation_code)

      # Next observations have no code, encounter, patient_id
      insert(:observation, patient_id: patient._id, context: context)
      insert(:observation, context: context)
      insert(:observation)

      request_params = %{
        "code" => code,
        "encounter_id" => encounter.id,
        "episode_id" => episode.id
      }

      response =
        conn
        |> get(observation_path(conn, :index, patient._id), request_params)
        |> json_response(200)

      assert 2 == response["paging"]["total_entries"]
    end

    test "success by code", %{conn: conn} do
      episode = build(:episode)
      patient = insert(:patient, episodes: [episode])
      expect_get_person_data(patient._id)
      {code, observation_code} = build_observation_code()

      insert(:observation, patient_id: patient._id, code: observation_code)
      insert(:observation, patient_id: patient._id, code: observation_code)

      # Next observations have no code, patient_id
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

    test "success by encounter and episode_id", %{conn: conn} do
      episode = build(:episode)
      patient = insert(:patient, episodes: %{episode.id => episode})
      expect_get_person_data(patient._id)
      {encounter_id, context} = build_encounter_id()

      insert(:observation, patient_id: patient._id, context: context)
      insert(:observation, patient_id: patient._id, context: context)
      insert(:observation, patient_id: patient._id, context: context)

      # Next observations have no encounter_id, episode_id
      insert(:observation, patient_id: patient._id)
      insert(:observation, patient_id: patient._id)

      request_params = %{
        "episode_id" => episode.id,
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

    test "success by patient_id with pagination", %{conn: conn} do
      patient = insert(:patient)
      expect_get_person_data(patient._id, 2)
      for _ <- 1..11, do: insert(:observation, patient_id: patient._id)
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

  defp build_encounter_id do
    encounter_id = UUID.uuid4()
    context = build(:reference, identifier: build(:identifier, value: encounter_id))
    {encounter_id, context}
  end
end
