defmodule Core.Jobs do
  @moduledoc false

  alias BSON.ObjectId
  alias Core.Job
  alias Core.Mongo
  alias Core.Mongo.Transaction
  require Logger

  @collection Job.collection()

  def produce_update_status(job, response, 200) do
    do_produce_update_status(job, cut_response(response), Job.status(:processed), 200)
  end

  def produce_update_status(job, response, status_code) do
    do_produce_update_status(job, cut_response(response), Job.status(:failed), status_code)
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

  defp do_produce_update_status(job, response, status, status_code) do
    %Transaction{patient_id: Map.get(job, :patient_id_hash)}
    |> update(job._id, status, response, status_code)
    |> Transaction.flush()
  end

  def get_by_id(id) when is_binary(id) do
    object_id = ObjectId.decode!(id)

    with %{} = job <- Mongo.find_one(@collection, %{"_id" => object_id}) do
      {:ok, map_to_job(job)}
    end
  rescue
    _ in FunctionClauseError -> nil
  end

  def update(%Transaction{} = transaction, id, status, response, status_code) when is_binary(id) do
    set_data = %{
      "status" => status,
      "status_code" => status_code,
      "updated_at" => DateTime.utc_now(),
      "response" => response
    }

    id = ObjectId.decode!(id)

    Transaction.add_operation(transaction, "jobs", :update, %{"_id" => id}, %{"$set" => set_data}, id)
  end

  def create(actor_id, patient_id, module, data) do
    hash = :md5 |> :crypto.hash(:erlang.term_to_binary(data)) |> Base.url_encode64(padding: false)

    case Mongo.find_one(@collection, %{"hash" => hash, "status" => Job.status(:pending)}, projection: [_id: true]) do
      %{"_id" => id} ->
        {:job_exists, to_string(id)}

      _ ->
        job = %Job{
          _id: Mongo.generate_id(),
          hash: hash,
          status: Job.status(:pending),
          status_code: 202,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          eta: count_eta(),
          response: ""
        }

        data =
          data
          |> Enum.into(%{}, fn {k, v} -> {String.to_atom(k), v} end)
          |> Map.put(:_id, to_string(job._id))
          |> Map.put(:request_id, Logger.metadata()[:request_id])

        result =
          %Transaction{actor_id: actor_id, patient_id: patient_id}
          |> Transaction.add_operation("jobs", :insert, job, job._id)
          |> Transaction.flush()

        case result do
          :ok ->
            {:ok, job, struct(module, data)}

          {:error, reason} ->
            Logger.error(reason)
            {:error, "Internal error"}
        end
    end
  end

  def complete(%Transaction{} = transaction, job) do
    case Transaction.flush(transaction) do
      :ok ->
        :ok

      {:error, reason} ->
        produce_update_status(job, reason, 500)
    end
  end

  # ToDo: count real eta based on kafka performance testing. Temporary hardcoded to 10 minutes.
  defp count_eta do
    DateTime.add(DateTime.utc_now(), 60_000)
  end

  defp map_to_job(data) do
    struct(Job, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end
