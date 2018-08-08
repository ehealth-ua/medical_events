defmodule Api.Web.VisitControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase
  alias Core.Patient
  import Mox

  describe "create visit" do
    test "patient not found", %{conn: conn} do
      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      conn = post(conn, visit_path(conn, :create, UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      patient = build(:patient, status: Patient.status(:inactive))
      assert {:ok, _} = Mongo.insert_one(patient)

      conn = post(conn, visit_path(conn, :create, patient._id))
      assert json_response(conn, 409)
    end

    test "no signed data set", %{conn: conn} do
      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      patient = build(:patient)
      assert {:ok, _} = Mongo.insert_one(patient)

      conn = post(conn, visit_path(conn, :create, patient._id))
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
      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      expect(KafkaMock, :publish_medical_event, fn _ -> :ok end)
      patient = build(:patient)
      assert {:ok, _} = Mongo.insert_one(patient)

      conn =
        post(conn, visit_path(conn, :create, patient._id), %{
          "signed_data" => [Base.encode64(Jason.encode!(%{}))]
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
end
