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

      user_id ->
        put_private(conn, :user_id, user_id)
    end
  end
end
