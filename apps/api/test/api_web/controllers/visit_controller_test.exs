defmodule Api.Web.VisitControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase
  import Mox

  describe "create visit" do
    test "success create visit", %{conn: conn} do
      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      conn = post(conn, visit_path(conn, :create))
      assert response = json_response(conn, 422)

      assert [
               %{
                 "entry" => "$.period",
                 "entry_type" => "json_data_property",
                 "rules" => [
                   %{
                     "description" => "required property period was not present",
                     "params" => [],
                     "rule" => "required"
                   }
                 ]
               }
             ] = response["error"]["invalid"]
    end
  end
end
