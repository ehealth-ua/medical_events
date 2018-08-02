defmodule Core.Requests do
  @moduledoc false

  alias Core.Mongo
  alias Core.Request

  def create(module, data) do
    id = :md5 |> :crypto.hash(:erlang.term_to_binary(data)) |> Base.encode64()

    request = %Request{
      _id: id,
      status: Request.status(:processing),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    data =
      data
      |> Enum.into(%{}, fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.put(:id, id)

    with {:ok, _} <- Mongo.insert_one(request) do
      {:ok, request, struct(module, data)}
    end
  end
end
