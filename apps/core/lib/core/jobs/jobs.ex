defmodule Core.Jobs do
  @moduledoc false

  alias Core.Job
  alias Core.Mongo

  @collection Job.metadata().collection

  def get_by_id(id) do
    with %{} = job <- Mongo.find_one(@collection, %{"_id" => id}) do
      {:ok, create_job(job)}
    end
  end

  def update(id, status, response) do
    set_data =
      Job.encode_response(%{
        "status" => status,
        "updated_at" => DateTime.utc_now(),
        "response" => response
      })

    Mongo.update_one(@collection, %{"_id" => id}, %{"$set" => set_data})
  end

  def create(module, data) do
    id = :md5 |> :crypto.hash(:erlang.term_to_binary(data)) |> Base.encode64(padding: false)

    job =
      Job.encode_response(%Job{
        _id: id,
        status: Job.status(:pending),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        response: ""
      })

    data =
      data
      |> Enum.into(%{}, fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.put(:_id, id)

    with {:ok, _} <- Mongo.insert_one(job) do
      {:ok, job, struct(module, data)}
    end
  end

  defp create_job(data) do
    Job
    |> struct(Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
    |> Job.decode_response()
  end
end
