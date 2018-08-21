defmodule Api.Plugs.Headers do
  @moduledoc false

  alias EView.Views.Error
  alias Plug.Conn
  import Core.Headers
  import Plug.Conn
  import Phoenix.Controller

  def required_header(%Conn{} = conn, header) do
    case get_header(conn.req_headers, header) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> render(Error, :"401", %{
          message: "Missing header #{header}",
          invalid: [
            %{
              entry_type: :header,
              entry: header
            }
          ]
        })
        |> halt()

      _ ->
        conn
    end
  end

  def put_user_id(%Conn{} = conn, _) do
    put_private(conn, :user_id, get_header(conn.req_headers, consumer_id()))
  end

  def put_client_id(%Conn{} = conn, _) do
    case get_header(conn.req_headers, consumer_metadata()) do
      nil ->
        conn

      consumer_metadata ->
        case Jason.decode(consumer_metadata) do
          {:ok, data} -> put_private(conn, :client_id, Map.get(data, "client_id"))
          _ -> conn
        end
    end
  end
end
