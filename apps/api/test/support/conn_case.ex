defmodule ApiWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common datastructures and query the data layer.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  alias Core.Headers

  using do
    quote do
      # Import conveniences for testing with connections
      use Phoenix.ConnTest
      import ApiWeb.ConnCase
      import ApiWeb.Router.Helpers
      import Core.Factories
      alias Core.Mongo

      # The default endpoint for testing
      @endpoint ApiWeb.Endpoint
    end
  end

  setup _tags do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> put_consumer_id_header()

    {:ok, conn: conn}
  end

  def put_consumer_id_header(conn, id \\ UUID.uuid4()) do
    Plug.Conn.put_req_header(conn, Headers.consumer_id(), id)
  end

  def put_client_id_header(conn, id \\ UUID.uuid4()) do
    Plug.Conn.put_req_header(conn, Headers.consumer_metadata(), Jason.encode!(%{"client_id" => id}))
  end

  def assert_json_schema(data, name) do
    assert :ok ==
             name
             |> schema_path()
             |> File.read!()
             |> Jason.decode!()
             |> NExJsonSchema.Validator.validate(data)

    data
  end

  defp schema_path(name) do
    File.cwd!() <> "/test/data/" <> name
  end
end
