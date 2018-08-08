defmodule Core.Requests do
  @moduledoc false

  alias Core.Mongo
  alias Core.Request

  @collection Request.metadata().collection

  def get_by_id(id) do
    with %{} = request <- Mongo.find_one(@collection, %{"_id" => id}) do
      {:ok, create_request(request)}
    end
  end

  def update(id, status, response) do
    set_data =
      Request.encode_response(%{
        "status" => status,
        "updated_at" => DateTime.utc_now(),
        "response" => response
      })

    Mongo.update_one(@collection, %{"_id" => id}, %{"$set" => set_data})
  end

  def create(module, data) do
    id = :md5 |> :crypto.hash(:erlang.term_to_binary(data)) |> Base.encode64(padding: false)

    request =
      Request.encode_response(%Request{
        _id: id,
        status: Request.status(:pending),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        response: ""
      })

    data =
      data
      |> Enum.into(%{}, fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.put(:_id, id)

    with {:ok, _} <- Mongo.insert_one(request) do
      {:ok, request, struct(module, data)}
    end
  end

  defp create_request(data) do
    Request
    |> struct(Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
    |> Request.decode_response()
  end
end
