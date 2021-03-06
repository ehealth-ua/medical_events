defmodule Core.Patients.AllergyIntolerances do
  @moduledoc false

  alias Core.AllergyIntolerance
  alias Core.Maybe
  alias Core.Mongo
  alias Core.Paging
  alias Core.Patient
  alias Core.Patients.Encounters
  alias Core.Search
  alias Core.Validators.JsonSchema
  alias Scrivener.Page
  require Logger

  @collection Patient.collection()

  def get_by_id(patient_id_hash, id) do
    with %{"allergy_intolerances" => %{^id => allergy_intolerance}} <-
           Mongo.find_one(
             @collection,
             %{
               "_id" => patient_id_hash,
               "allergy_intolerances.#{id}" => %{"$exists" => true}
             },
             projection: ["allergy_intolerances.#{id}": true]
           ) do
      {:ok, AllergyIntolerance.create(allergy_intolerance)}
    else
      _ ->
        nil
    end
  end

  def get_by_id_episode_id(patient_id_hash, id, episode_id) do
    encounter_ids = get_encounter_ids(patient_id_hash, Mongo.string_to_uuid(episode_id))

    pipeline = [
      %{
        "$match" => %{
          "_id" => patient_id_hash
        }
      },
      %{"$project" => %{"allergy_intolerances" => %{"$objectToArray" => "$allergy_intolerances"}}},
      %{"$unwind" => "$allergy_intolerances"},
      %{
        "$match" => %{
          "allergy_intolerances.k" => id,
          "allergy_intolerances.v.context.identifier.value" => %{"$in" => encounter_ids}
        }
      },
      %{
        "$project" => %{"allergy_intolerance" => "$allergy_intolerances.v"}
      }
    ]

    with [%{"allergy_intolerance" => allergy_intolerance}] <- @collection |> Mongo.aggregate(pipeline) |> Enum.to_list() do
      {:ok, AllergyIntolerance.create(allergy_intolerance)}
    else
      _ ->
        nil
    end
  end

  def list(%{"patient_id_hash" => patient_id_hash} = params, schema \\ :allergy_intolerance_request) do
    with :ok <- JsonSchema.validate(schema, Map.drop(params, ~w(page page_size patient_id patient_id_hash))) do
      pipeline =
        [
          %{"$match" => %{"_id" => patient_id_hash}},
          %{"$project" => %{"allergy_intolerances" => %{"$objectToArray" => "$allergy_intolerances"}}},
          %{"$unwind" => "$allergy_intolerances"}
        ]
        |> add_search_pipeline(patient_id_hash, params)
        |> Enum.concat([
          %{"$project" => %{"allergy_intolerance" => "$allergy_intolerances.v"}},
          %{"$replaceRoot" => %{"newRoot" => "$allergy_intolerance"}},
          %{"$sort" => %{"inserted_at" => -1}}
        ])

      with %Page{entries: allergy_intolerances} = paging <-
             Paging.paginate(:aggregate, @collection, pipeline, Map.take(params, ~w(page page_size))) do
        {:ok, %Page{paging | entries: Enum.map(allergy_intolerances, &AllergyIntolerance.create/1)}}
      end
    end
  end

  defp add_search_pipeline(pipeline, patient_id_hash, params) do
    path = "allergy_intolerances.v"
    encounter_id = Maybe.map(params["encounter_id"], &Mongo.string_to_uuid(&1))
    onset_date_time_from = Search.get_filter_date(:from, params["onset_date_time_from"])
    onset_date_time_to = Search.get_filter_date(:to, params["onset_date_time_to"])

    episode_id = if params["episode_id"], do: Mongo.string_to_uuid(params["episode_id"])
    encounter_ids = if !is_nil(episode_id), do: get_encounter_ids(patient_id_hash, episode_id)

    search_pipeline =
      %{"$match" => %{}}
      |> Search.add_param(%{"code" => params["code"]}, ["$match", "#{path}.code.coding"], "$elemMatch")
      |> Search.add_param(encounter_id, ["$match", "#{path}.context.identifier.value"])
      |> add_search_param(encounter_ids, ["$match", "#{path}.context.identifier.value"], "$in")
      |> Search.add_param(onset_date_time_from, ["$match", "#{path}.onset_date_time"], "$gte")
      |> Search.add_param(onset_date_time_to, ["$match", "#{path}.onset_date_time"], "$lt")

    search_pipeline
    |> Map.get("$match", %{})
    |> Map.keys()
    |> case do
      [] -> pipeline
      _ -> pipeline ++ [search_pipeline]
    end
  end

  def get_encounter_ids(patient_id_hash, episode_id) do
    patient_id_hash
    |> Encounters.get_episode_encounters(episode_id)
    |> Enum.map(& &1["encounter_id"])
    |> Enum.uniq()
  end

  defp add_search_param(search_params, nil, _path, _operator), do: search_params

  defp add_search_param(search_params, value, path, operator) do
    if get_in(search_params, path) == nil do
      put_in(search_params, path, %{operator => value})
    else
      update_in(search_params, path, &Map.merge(&1, %{operator => value}))
    end
  end

  def get_by_encounter_id(patient_id_hash, %BSON.Binary{} = encounter_id) do
    @collection
    |> Mongo.aggregate([
      %{"$match" => %{"_id" => patient_id_hash}},
      %{"$project" => %{"allergy_intolerances" => %{"$objectToArray" => "$allergy_intolerances"}}},
      %{"$unwind" => "$allergy_intolerances"},
      %{"$match" => %{"allergy_intolerances.v.context.identifier.value" => encounter_id}},
      %{"$replaceRoot" => %{"newRoot" => "$allergy_intolerances.v"}}
    ])
    |> Enum.map(&AllergyIntolerance.create/1)
  end
end
