defmodule Core.Jobs do
  @moduledoc false

  alias BSON.ObjectId
  alias Core.Job
  alias Core.Mongo

  @collection Job.metadata().collection

  def get_by_id(id) when is_binary(id) do
    object_id = ObjectId.decode!(id)

    with %{} = job <- Mongo.find_one(@collection, %{"_id" => object_id}) do
      {:ok, map_to_job(job)}
    end
  rescue
    _ in FunctionClauseError -> nil
  end

  def update(id, status, response, status_code) when is_binary(id) do
    set_data =
      Job.encode_response(%{
        "status" => status,
        "status_code" => status_code,
        "updated_at" => DateTime.utc_now(),
        "response" => response
      })

    Mongo.update_one(@collection, %{"_id" => ObjectId.decode!(id)}, %{"$set" => set_data})
  rescue
    _ in FunctionClauseError -> nil
  end

  def create(module, data) do
    hash = :md5 |> :crypto.hash(:erlang.term_to_binary(data)) |> Base.url_encode64(padding: false)

    case Mongo.find_one(@collection, %{"hash" => hash, "status" => Job.status(:pending)}, projection: [_id: true]) do
      %{"_id" => id} ->
        {:job_exists, to_string(id)}

      _ ->
        job =
          Job.encode_response(%Job{
            _id: Mongo.generate_id(),
            hash: hash,
            status: Job.status(:pending),
            status_code: 202,
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now(),
            eta: count_eta(),
            response: ""
          })

        data =
          data
          |> Enum.into(%{}, fn {k, v} -> {String.to_atom(k), v} end)
          |> Map.put(:_id, to_string(job._id))

        with {:ok, _} <- Mongo.insert_one(job) do
          {:ok, job, struct(module, data)}
        end
    end
  end

  # ToDo: count real eta based on kafka performance testing. Temporary hardcoded to 10 minutes.
  defp count_eta do
    time = :os.system_time(:millisecond) + 60_000

    time
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
  end

  defp map_to_job(data) do
    Job
    |> struct(Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
    |> Job.decode_response()
  end

  def fetch_links(%Job{status_code: 200, response: response}), do: Map.get(response, "links", [])

  def fetch_links(%Job{_id: id}),
    do: [
      %{
        entity: "job",
        href: "/jobs/#{id}"
      }
    ]
end
