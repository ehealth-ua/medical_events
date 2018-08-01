defmodule Api.Web.FallbackController do
  @moduledoc false

  use ApiWeb, :controller

  alias EView.Views.ValidationError

  def call(conn, {:error, errors}) when is_list(errors) do
    conn
    |> put_status(422)
    |> render(ValidationError, "422.json", %{schema: errors})
  end
end
