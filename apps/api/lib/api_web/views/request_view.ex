defmodule Api.Web.RequestView do
  @moduledoc false

  use ApiWeb, :view
  alias Core.Request

  def render("create.json", %{request: %Request{_id: id, status: status}}) do
    %{"id" => BSON.ObjectId.encode!(id), "status" => status}
  end
end
