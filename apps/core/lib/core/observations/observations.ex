defmodule Core.Observations do
  @moduledoc false

  alias Core.Mongo
  alias Core.Observation
  alias Core.Paging
  alias Core.Patient
  alias Scrivener.Page

  @observation_collection Observation.metadata().collection
  @patient_collection Patient.metadata().collection

  def get_by_id(patient_id, id) do
    @observation_collection
    |> Mongo.find_one(%{"_id" => id, "patient_id" => patient_id})
    |> case do
      %{} = observation -> {:ok, Observation.create(observation)}
      _ -> nil
    end
  end

  def list(params) do
    paging_params = Map.take(params, ["page", "page_size"])

    with %Page{entries: observations} = page <-
           Paging.paginate(:aggregate, @observation_collection, search_observations_pipe(params), paging_params) do
      {:ok, %Page{page | entries: Enum.map(observations, &Observation.create/1)}}
    end
  end

  defp search_observations_pipe(%{"patient_id" => patient_id} = params) do
    code = params["code"]
    episode_id = params["episode_id"]

    encounter_ids = get_encounter_ids(patient_id, episode_id)

    encounter_ids =
      case params["encounter_id"] do
        nil -> encounter_ids
        encounter_id -> Enum.uniq([encounter_id | encounter_ids])
      end

    %{"$match" => %{"patient_id" => patient_id}}
    |> add_search_param(code, ["$match", "code.coding.0.code"])
    |> add_search_param(encounter_ids, ["$match", "context.identifier.value"], "$in")
    |> List.wrap()
    |> Enum.concat([%{"$sort" => %{"inserted_at" => -1}}])
  end

  def get_encounter_ids(_patient_id, nil), do: []

  def get_encounter_ids(patient_id, episode_id) do
    pipeline = [
      %{
        "$match" => %{
          "_id" => patient_id
        }
      },
      %{"$project" => %{"encounters" => %{"$objectToArray" => "$encounters"}}},
      %{"$unwind" => "$encounters"},
      %{
        "$project" => %{
          "episode_id" => "$encounters.v.episode.identifier.value",
          "encounter_id" => "$encounters.v.id"
        }
      },
      %{
        "$match" => %{
          "episode_id" => episode_id
        }
      }
    ]

    @patient_collection
    |> Mongo.aggregate(pipeline)
    |> Enum.map(& &1["encounter_id"])
  end

  defp add_search_param(search_params, value, path, operator \\ "$eq")
  defp add_search_param(search_params, nil, _path, _operator), do: search_params
  defp add_search_param(search_params, [], _path, _operator), do: search_params
  defp add_search_param(search_params, value, path, operator), do: put_in(search_params, path, %{operator => value})
end
