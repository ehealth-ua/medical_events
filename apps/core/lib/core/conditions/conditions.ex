defmodule Core.Conditions do
  @moduledoc false

  alias Core.Condition
  alias Core.Maybe
  alias Core.Mongo
  alias Core.Paging
  alias Core.Search
  alias Core.Validators.JsonSchema
  alias Scrivener.Page
  require Logger

  @condition_collection Condition.collection()

  def get_by_id(patient_id_hash, id, opts \\ []) do
    @condition_collection
    |> Mongo.find_one(%{"_id" => Mongo.string_to_uuid(id), "patient_id" => patient_id_hash}, opts)
    |> case do
      %{} = condition -> {:ok, Condition.create(condition)}
      _ -> nil
    end
  end

  def get_by_id_episode_id(patient_id_hash, id, episode_id) do
    @condition_collection
    |> Mongo.find_one(%{
      "_id" => Mongo.string_to_uuid(id),
      "patient_id" => patient_id_hash,
      "context_episode_id" => Mongo.string_to_uuid(episode_id)
    })
    |> case do
      %{} = condition -> {:ok, Condition.create(condition)}
      _ -> nil
    end
  end

  def get_summary(patient_id_hash, id) do
    @condition_collection
    |> Mongo.find_one(%{
      "_id" => Mongo.string_to_uuid(id),
      "patient_id" => patient_id_hash,
      "code.coding.code" => %{"$in" => Confex.fetch_env!(:core, :summary)[:conditions_whitelist]}
    })
    |> case do
      %{} = condition -> {:ok, Condition.create(condition)}
      _ -> nil
    end
  end

  def get_by_encounter_id(patient_id_hash, %BSON.Binary{} = encounter_id) do
    @condition_collection
    |> Mongo.find(%{"patient_id" => patient_id_hash, "context.identifier.value" => encounter_id})
    |> Enum.map(&Condition.create/1)
  end

  def list(params) do
    json_params = Map.drop(params, ~w(page page_size patient_id patient_id_hash))

    with :ok <- JsonSchema.validate(:condition_request, json_params) do
      paging_params = Map.take(params, ~w(page page_size))

      with [_ | _] = pipeline <- search_conditions_pipe(params),
           %Page{entries: conditions} = page <-
             Paging.paginate(:aggregate, @condition_collection, pipeline, paging_params) do
        {:ok, %Page{page | entries: Enum.map(conditions, &Condition.create/1)}}
      else
        _ -> {:ok, Paging.create()}
      end
    end
  end

  def summary(params) do
    json_params = Map.drop(params, ~w(page page_size patient_id patient_id_hash))

    with :ok <- JsonSchema.validate(:condition_summary, json_params) do
      paging_params = Map.take(params, ~w(page page_size))

      with [_ | _] = pipeline <- search_conditions_summary(params),
           %Page{entries: conditions} = page <-
             Paging.paginate(:aggregate, @condition_collection, pipeline, paging_params) do
        {:ok, %Page{page | entries: Enum.map(conditions, &Condition.create/1)}}
      else
        _ -> {:ok, Paging.create()}
      end
    end
  end

  defp search_conditions_pipe(%{"patient_id_hash" => patient_id_hash} = params) do
    code = params["code"]
    onset_date_from = filter_date(params["onset_date_from"])
    onset_date_to = filter_date(params["onset_date_to"], true)
    episode_id = Maybe.map(params["episode_id"], &Mongo.string_to_uuid(&1))
    encounter_id = Maybe.map(params["encounter_id"], &Mongo.string_to_uuid(&1))

    %{"$match" => %{"patient_id" => patient_id_hash}}
    |> Search.add_param(code, ["$match", "code.coding.0.code"])
    |> Search.add_param(encounter_id, ["$match", "context.identifier.value"])
    |> Search.add_param(episode_id, ["$match", "context_episode_id"])
    |> Search.add_param(onset_date_from, ["$match", "onset_date"], "$gte")
    |> Search.add_param(onset_date_to, ["$match", "onset_date"], "$lte")
    |> List.wrap()
    |> Enum.concat([%{"$sort" => %{"inserted_at" => -1}}])
  end

  defp search_conditions_summary(%{"patient_id_hash" => patient_id_hash} = params) do
    code = params["code"]
    codes = Confex.fetch_env!(:core, :summary)[:conditions_whitelist]
    onset_date_from = filter_date(params["onset_date_from"])
    onset_date_to = filter_date(params["onset_date_to"], true)

    %{"$match" => %{"patient_id" => patient_id_hash}}
    |> Search.add_param(code, ["$match", "code.coding.0.code"])
    |> Search.add_param(codes, ["$match", "code.coding.0.code"], "$in")
    |> Search.add_param(onset_date_from, ["$match", "onset_date"], "$gte")
    |> Search.add_param(onset_date_to, ["$match", "onset_date"], "$lte")
    |> List.wrap()
    |> Enum.concat([%{"$sort" => %{"inserted_at" => -1}}])
  end

  defp filter_date(date, end_day_time? \\ false) do
    time = (end_day_time? && "23:59:59") || "00:00:00"

    case DateTime.from_iso8601("#{date} #{time}Z") do
      {:ok, date_time, _} -> date_time
      _ -> nil
    end
  end
end
