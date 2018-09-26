defmodule Api.Web.Plugs.AuthorizePartyTest do
  @moduledoc false

  use ApiWeb.ConnCase

  import Core.Expectations.CasherExpectation
  import Mox

  alias Api.Web.Plugs.AuthorizeParty
  alias Api.Web.Plugs.Headers
  alias Core.Redis
  alias Core.Redis.StorageKeys

  describe "authorize party" do
    setup %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      user_id = UUID.uuid4()
      client_id = UUID.uuid4()

      conn =
        conn
        |> put_consumer_id_header(user_id)
        |> put_client_id_header(client_id)
        |> Headers.put_user_id([])
        |> Headers.put_client_id([])
        |> Map.put(:params, %{"_format" => "json"})

      {:ok, conn: conn, user_id: user_id, client_id: client_id}
    end

    test "success from casher", %{conn: conn} do
      patient = insert(:patient)
      expect_get_person_data(patient._id)

      assert %Plug.Conn{status: nil} =
               conn
               |> Map.put(:path_params, %{"patient_id" => patient._id})
               |> AuthorizeParty.call([])
    end

    test "success from redis", %{conn: conn, user_id: user_id, client_id: client_id} do
      patient = insert(:patient)

      Redis.setnx(StorageKeys.person_data(user_id, client_id), [patient._id])

      assert %Plug.Conn{status: nil} =
               conn
               |> Map.put(:path_params, %{"patient_id" => patient._id})
               |> AuthorizeParty.call([])
    end

    test "access denied: patient_id not found from redis and casher", %{conn: conn} do
      patient = insert(:patient)
      expect_get_person_data(patient._id)

      assert %Plug.Conn{status: 401, resp_body: resp_body} =
               conn
               |> Map.put(:path_params, %{"patient_id" => UUID.uuid4()})
               |> AuthorizeParty.call([])

      assert resp_body =~ "Access denied"
    end

    test "access denied: empty patient_ids list from redis", %{conn: conn, user_id: user_id, client_id: client_id} do
      Redis.setnx(StorageKeys.person_data(user_id, client_id), [])

      patient = insert(:patient)
      expect_get_person_data(patient._id)

      assert %Plug.Conn{status: 401, resp_body: resp_body} =
               conn
               |> Map.put(:path_params, %{"patient_id" => patient._id})
               |> AuthorizeParty.call([])

      assert resp_body =~ "Access denied"
    end

    test "patient not found", %{conn: conn} do
      patient_id = UUID.uuid4()
      expect_get_person_data(patient_id)

      assert %Plug.Conn{status: 404, resp_body: resp_body} =
               conn
               |> Map.put(:path_params, %{"patient_id" => patient_id})
               |> AuthorizeParty.call([])

      assert resp_body =~ "not_found"
    end
  end
end
