defmodule Api.Web.VisitControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase

  describe "create visit" do
    test "success create visit", %{conn: conn} do
      conn = post(conn, visit_path(conn, :create))
      # IO.inspect(json_response(conn, 201))
    end
  end
end
