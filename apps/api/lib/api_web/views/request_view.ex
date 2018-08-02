defmodule Api.Web.RequestView do
  @moduledoc false

  use ApiWeb, :view
  alias Core.Request

  def render("create.json", %{request: %Request{_id: id} = request}) do
    request
    |> Map.take(~w(id status inserted_at updated_at)a)
    |> Map.put("id", id)
  end
end
