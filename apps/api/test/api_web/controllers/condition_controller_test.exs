defmodule Api.Web.ConditionControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase

  import Core.Expectations.CasherExpectation
  import Mox

  setup %{conn: conn} do
    stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

    {:ok, conn: put_consumer_id_header(conn)}
  end

  describe "search conditions" do
    test "success by code, encounter_id, episode_id", %{conn: conn} do
      episode = build(:episode)
      patient = insert(:patient, episodes: [episode])
      expect_get_person_data(patient._id)

      {code, condition_code} = build_condition_code()
      {encounter_id, context} = build_encounter_id()

      insert(:condition, patient_id: patient._id, context: context, code: condition_code, asserted_date: nil)
      insert(:condition, patient_id: patient._id, context: context, code: condition_code)

      # Missed code, encounter, patient_id
      insert(:condition, patient_id: patient._id, context: context)
      insert(:condition, patient_id: patient._id)
      insert(:condition)

      request_params = %{
        "code" => code,
        "encounter_id" => encounter_id,
        "episode_id" => episode.id
      }

      response =
        conn
        |> get(condition_path(conn, :index, patient._id), request_params)
        |> json_response(200)
        |> assert_json_schema("conditions/conditions_list.json")

      Enum.each(response["data"], fn condition ->
        assert %{"context" => %{"identifier" => %{"value" => ^encounter_id}}} = condition
        assert %{"code" => %{"coding" => [%{"code" => ^code}]}} = condition
      end)

      assert 2 == response["paging"]["total_entries"]
    end

    test "success by code", %{conn: conn} do
      episode = build(:episode)
      patient = insert(:patient, episodes: [episode])
      expect_get_person_data(patient._id)
      {code, condition_code} = build_condition_code()

      insert(:condition, patient_id: patient._id, code: condition_code)
      insert(:condition, patient_id: patient._id, code: condition_code)

      # Have no code, patient_id
      insert(:condition, patient_id: patient._id)
      insert(:condition)

      request_params = %{"code" => code}

      response =
        conn
        |> get(condition_path(conn, :index, patient._id), request_params)
        |> json_response(200)

      assert 2 == response["paging"]["total_entries"]

      Enum.each(response["data"], fn %{"code" => %{"coding" => [%{"code" => entity_code}]}} ->
        assert entity_code == code
      end)
    end

    test "success by encounter and episode_id", %{conn: conn} do
      episode = build(:episode)
      patient = insert(:patient, episodes: [episode])
      expect_get_person_data(patient._id)
      {encounter_id, context} = build_encounter_id()

      insert(:condition, patient_id: patient._id, context: context)
      insert(:condition, patient_id: patient._id, context: context)
      insert(:condition, patient_id: patient._id, context: context)

      # Have no encounter, episode_id
      insert(:condition, patient_id: patient._id)
      insert(:condition, patient_id: patient._id)

      request_params = %{
        "episode_id" => episode.id,
        "encounter_id" => encounter_id
      }

      response =
        conn
        |> get(condition_path(conn, :index, patient._id), request_params)
        |> json_response(200)

      assert 3 == get_in(response, ["paging", "total_entries"])

      Enum.each(response["data"], fn %{"context" => %{"identifier" => %{"value" => entity_encounter_id}}} ->
        assert entity_encounter_id == encounter_id
      end)
    end

    test "success by patient_id with pagination", %{conn: conn} do
      patient = insert(:patient)
      expect_get_person_data(patient._id, 2)

      for _ <- 1..11, do: insert(:condition, patient_id: patient._id)

      # defaults: paging = 50, page = 1
      assert %{
               "page_number" => 1,
               "page_size" => 50,
               "total_entries" => 11,
               "total_pages" => 1
             } ==
               conn
               |> get(condition_path(conn, :index, patient._id), %{})
               |> json_response(200)
               |> Map.get("paging")

      response =
        conn
        |> get(condition_path(conn, :index, patient._id), %{"page" => "2", "page_size" => "5"})
        |> json_response(200)

      assert %{"page_size" => 5, "page_number" => 2, "total_pages" => 3} = response["paging"]
      assert 5 == length(response["data"])
    end

    test "empty results", %{conn: conn} do
      patient = insert(:patient)
      expect_get_person_data(patient._id)

      insert(:condition)

      assert [] =
               conn
               |> get(condition_path(conn, :index, patient._id), %{})
               |> json_response(200)
               |> get_in(["data"])
    end
  end

  describe "get condition" do
    test "success", %{conn: conn} do
      patient = insert(:patient)
      condition = insert(:condition, patient_id: patient._id, asserted_date: nil)

      expect_get_person_data(patient._id)

      conn
      |> get(condition_path(conn, :show, patient._id, condition._id))
      |> json_response(200)
      |> assert_json_schema("conditions/condition_show.json")
    end

    test "condition not found", %{conn: conn} do
      patient = insert(:patient)
      expect_get_person_data(patient._id)

      conn
      |> get(condition_path(conn, :show, patient._id, UUID.uuid4()))
      |> json_response(404)
    end
  end

  defp build_condition_code do
    code = "A#{:rand.uniform(100)}"
    condition_code = build(:codeable_concept, coding: [build(:coding, code: code, system: "eHealth/ICD10/conditions")])

    {code, condition_code}
  end

  defp build_encounter_id do
    encounter_id = UUID.uuid4()

    context =
      build(:reference,
        identifier: build(:identifier, value: encounter_id, type: codeable_concept_coding(code: "encounter"))
      )

    {encounter_id, context}
  end
end
