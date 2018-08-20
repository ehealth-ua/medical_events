defmodule Api.Web.EpisodeControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase
  alias Core.Patient
  import Mox

  describe "create episode" do
    test "patient not found", %{conn: conn} do
      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      conn = post(conn, visit_path(conn, :create, UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      patient = build(:patient, status: Patient.status(:inactive))
      assert {:ok, _} = Mongo.insert_one(patient)

      conn = post(conn, visit_path(conn, :create, patient._id))
      assert json_response(conn, 409)
    end

    test "json schema validation failed", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      expect(KafkaMock, :publish_medical_event, fn _ -> :ok end)
      patient = build(:patient)
      assert {:ok, _} = Mongo.insert_one(patient)

      conn = post(conn, episode_path(conn, :create, patient._id), %{})
      assert json_response(conn, 422)
    end

    test "success create episode", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      expect(KafkaMock, :publish_medical_event, fn _ -> :ok end)
      patient = build(:patient)
      assert {:ok, _} = Mongo.insert_one(patient)

      conn =
        post(conn, episode_path(conn, :create, patient._id), %{
          "id" => UUID.uuid4(),
          "name" => "ОРВИ 2018",
          "type" => "primary_care",
          "managing_organization" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"system" => "eHealth", "code" => "episode"}]},
              "value" => UUID.uuid4()
            }
          },
          "period" => %{"start" => DateTime.to_iso8601(DateTime.utc_now())},
          "care_manager" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"system" => "eHealth", "code" => "episode"}]},
              "value" => UUID.uuid4()
            }
          }
        })

      assert response = json_response(conn, 202)
    end
  end
end
