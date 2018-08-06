defmodule Api.Web.RequestView do
  @moduledoc false

  use ApiWeb, :view
  alias Core.Request

  def render("create.json", %{request: %Request{_id: id, status: status} = request}) do
    request
    |> Map.take(~w(inserted_at updated_at)a)
    |> Map.put(:status, Request.status_to_string(status))
    |> Map.put(:id, id)
  end
end
