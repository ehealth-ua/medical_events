defmodule Core.Jobs do
  @moduledoc false

  alias BSON.ObjectId
  alias Core.Job
  alias Core.Jobs.JobUpdateStatusJob
  alias Core.Mongo
  require Logger

  @collection Job.metadata().collection
  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  def produce_update_status(id, request_id, response, 200) do
    do_produce_update_status(id, request_id, cut_response(response), Job.status(:processed), 200)
  end

  def produce_update_status(id, request_id, response, status_code) do
    do_produce_update_status(id, request_id, cut_response(response), Job.status(:failed), status_code)
  end

  def cut_response(%{invalid: errors} = response) do
    with {false, _} <- {Job.valid_response?(response), response},
         updated_response <- %{response | invalid: Enum.map(errors, &cut_params/1)},
         {false, updated_response} <- {Job.valid_response?(updated_response), updated_response} do
      cut_response(%{updated_response | invalid: Enum.take(updated_response.invalid, Enum.count(errors) - 1)})
    else
      {_, response} -> response
    end
  end

  def cut_response(%{"invalid" => errors} = response) do
    with {false, _} <- {Job.valid_response?(response), response},
         updated_response <- %{response | "invalid" => Enum.map(errors, &cut_params/1)},
         {false, updated_response} <- {Job.valid_response?(updated_response), updated_response} do
      cut_response(%{updated_response | "invalid" => Enum.take(updated_response.invalid, Enum.count(errors) - 1)})
    else
      {_, response} -> response
    end
  end

  def cut_response(response) when is_binary(response) do
    if Job.valid_response?(response), do: response, else: String.slice(response, 0, Job.response_length() - 3) <> "..."
  end

  def cut_response(%{"error" => error} = response) when is_binary(error) do
    if Job.valid_response?(response) do
      response
    else
      %{"error" => String.slice(error, 0, Job.response_length() - 3) <> "..."}
    end
  end

  def cut_response(response), do: response

  defp cut_params(%{rules: rules} = error) do
    updated_rules = Enum.map(rules, &Map.put(&1, :params, []))
    %{error | rules: updated_rules}
  end

  defp cut_params(%{"rules" => rules} = error) do
    updated_rules = Enum.map(rules, &Map.put(&1, "params", []))
    %{error | "rules" => updated_rules}
  end

  defp cut_params(error), do: error

  defp do_produce_update_status(id, request_id, response, status, status_code) do
    event = %JobUpdateStatusJob{
      request_id: request_id,
      _id: id,
      response: response,
      status: status,
      status_code: status_code
    }

    with :ok <- @kafka_producer.publish_job_update_status_event(event) do
      :ok
    else
      error ->
        Logger.error("Failed to publish kafka event: #{inspect(error)}")
        update_status(event)
    end
  end

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
          |> Map.put(:request_id, Logger.metadata()[:request_id])

        with {:ok, _} <- Mongo.insert_one(job) do
          {:ok, job, struct(module, data)}
        end
    end
  end

  def update_status(%JobUpdateStatusJob{_id: id} = event) do
    case get_by_id(id) do
      {:ok, _} ->
        {:ok, %{matched_count: 1, modified_count: 1}} = update(id, event.status, event.response, event.status_code)
        :ok

      _ ->
        Logger.warn(fn -> "Can't get job by id #{id}" end)
        :ok
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
