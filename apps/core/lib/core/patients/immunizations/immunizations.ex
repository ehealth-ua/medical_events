defmodule Core.Patients.Immunizations do
  @moduledoc false

  alias Core.Immunization
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
    with %{"immunizations" => %{^id => immunization}} <-
           Mongo.find_one(
             @collection,
             %{
               "_id" => patient_id_hash,
               "immunizations.#{id}" => %{"$exists" => true}
             },
             projection: ["immunizations.#{id}": true]
           ) do
      {:ok, Immunization.create(immunization)}
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
      %{"$project" => %{"immunizations" => %{"$objectToArray" => "$immunizations"}}},
      %{"$unwind" => "$immunizations"},
      %{
        "$match" => %{
          "immunizations.k" => id,
          "immunizations.v.context.identifier.value" => %{"$in" => encounter_ids}
        }
      },
      %{
        "$project" => %{"immunization" => "$immunizations.v"}
      }
    ]

    with [%{"immunization" => immunization}] <- @collection |> Mongo.aggregate(pipeline) |> Enum.to_list() do
      {:ok, Immunization.create(immunization)}
    else
      _ ->
        nil
    end
  end

  def get_by_ids(_patient_id_hash, []), do: {:ok, []}

  def get_by_ids(patient_id_hash, ids) do
    with %{"immunizations" => immunizations} <-
           Mongo.find_one(@collection, %{"_id" => patient_id_hash}, projection: [immunizations: true]) do
      immunizations = Enum.into(immunizations, %{})

      immunizations =
        Enum.reduce_while(ids, [], fn id, acc ->
          case Map.fetch(immunizations, id) do
            {:ok, immunization} -> {:cont, [Immunization.create(immunization) | acc]}
            :error -> {:halt, {:error, "Immunization with id: #{id} not found"}}
          end
        end)

      case immunizations do
        {:error, _} = error -> error
        immunizations -> {:ok, immunizations}
      end
    else
      _ -> {:error, "Immunization with id: #{hd(ids)} not found"}
    end
  end

  def list(%{"patient_id_hash" => patient_id_hash} = params, schema \\ :immunization_request) do
    with :ok <- JsonSchema.validate(schema, Map.drop(params, ~w(page page_size patient_id patient_id_hash))) do
      pipeline =
        [
          %{"$match" => %{"_id" => patient_id_hash}},
          %{"$project" => %{"immunizations" => %{"$objectToArray" => "$immunizations"}}},
          %{"$unwind" => "$immunizations"}
        ]
        |> add_search_pipeline(patient_id_hash, params)
        |> Enum.concat([
          %{"$project" => %{"immunization" => "$immunizations.v"}},
          %{"$replaceRoot" => %{"newRoot" => "$immunization"}},
          %{"$sort" => %{"inserted_at" => -1}}
        ])

      with %Page{entries: immunizations} = paging <-
             Paging.paginate(:aggregate, @collection, pipeline, Map.take(params, ~w(page page_size))) do
        {:ok, %Page{paging | entries: Enum.map(immunizations, &Immunization.create/1)}}
      end
    end
  end

  defp add_search_pipeline(pipeline, patient_id_hash, params) do
    path = "immunizations.v"
    encounter_id = Maybe.map(params["encounter_id"], &Mongo.string_to_uuid(&1))
    date_from = Search.get_filter_date(:from, params["date_from"])
    date_to = Search.get_filter_date(:to, params["date_to"])

    episode_id = if params["episode_id"], do: Mongo.string_to_uuid(params["episode_id"])
    encounter_ids = if !is_nil(episode_id), do: get_encounter_ids(patient_id_hash, episode_id)

    search_pipeline =
      %{"$match" => %{}}
      |> Search.add_param(%{"code" => params["vaccine_code"]}, ["$match", "#{path}.vaccine_code.coding"], "$elemMatch")
      |> Search.add_param(encounter_id, ["$match", "#{path}.context.identifier.value"])
      |> add_search_param(encounter_ids, ["$match", "#{path}.context.identifier.value"], "$in")
      |> Search.add_param(date_from, ["$match", "#{path}.date"], "$gte")
      |> Search.add_param(date_to, ["$match", "#{path}.date"], "$lt")

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
      %{"$project" => %{"immunizations" => %{"$objectToArray" => "$immunizations"}}},
      %{"$unwind" => "$immunizations"},
      %{"$match" => %{"immunizations.v.context.identifier.value" => encounter_id}},
      %{"$replaceRoot" => %{"newRoot" => "$immunizations.v"}}
    ])
    |> Enum.map(&Immunization.create/1)
  end
end
