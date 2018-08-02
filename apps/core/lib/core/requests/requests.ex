defmodule Core.Requests do
  @moduledoc false

  alias Core.Mongo
  alias Core.Request

  def create(data) do
    request = %Request{_id: Mongo.object_id(), status: Request.status(:processing)}

    with {:ok, _} <- Mongo.insert_one(request) do
      {:ok, request}
    end
  end
end
