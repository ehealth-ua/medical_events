defmodule Api.Web.VisitControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase
  import Mox

  describe "create visit" do
    test "no signed data set", %{conn: conn} do
      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      conn = post(conn, visit_path(conn, :create))
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

      conn =
        post(conn, visit_path(conn, :create), %{
          "signed_data" => [%{"id" => UUID.uuid4(), "signed_content" => Base.encode64(Jason.encode!(%{}))}]
        })

      assert response = json_response(conn, 201)

      assert %{
               "data" => %{
                 "id" => _,
                 "inserted_at" => _,
                 "status" => "processing",
                 "updated_at" => _
               }
             } = response
    end
  end
end
