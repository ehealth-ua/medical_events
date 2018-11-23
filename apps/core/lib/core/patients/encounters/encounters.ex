defmodule Core.Patients.Encounters do
  @moduledoc false

  alias Core.Encounter
  alias Core.Maybe
  alias Core.Mongo
  alias Core.Paging
  alias Core.Patient
  alias Core.Search
  alias Scrivener.Page
  require Logger

  @patient_collection Patient.metadata().collection

  def get_by_id(patient_id_hash, id) do
    with %{"encounters" => %{^id => encounter}} <-
           Mongo.find_one(@patient_collection, %{"_id" => patient_id_hash}, projection: ["encounters.#{id}": true]) do
      {:ok, Encounter.create(encounter)}
    else
      _ ->
        nil
    end
  end

  def get_episode_encounters(
        patient_id_hash,
        %BSON.Binary{} = episode_id,
        project \\ %{
          "episode_id" => "$encounters.v.episode.identifier.value",
          "encounter_id" => "$encounters.v.id"
        }
      ) do
    pipeline = [
      %{
        "$match" => %{
          "_id" => patient_id_hash
        }
      },
      %{"$project" => %{"encounters" => %{"$objectToArray" => "$encounters"}}},
      %{"$unwind" => "$encounters"},
      %{
        "$match" => %{
          "encounters.v.episode.identifier.value" => episode_id
        }
      },
      %{
        "$project" => project
      }
    ]

    @patient_collection
    |> Mongo.aggregate(pipeline)
    |> Enum.to_list()
  end

  def fill_up_encounter_performer(%Encounter{performer: performer} = encounter) do
    with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{performer.identifier.value}") do
      first_name = get_in(employee, ~w(party first_name)a)
      second_name = get_in(employee, ~w(party second_name)a)
      last_name = get_in(employee, ~w(party last_name)a)

      %{encounter | performer: %{performer | display_value: "#{first_name} #{second_name} #{last_name}"}}
    else
      _ ->
        Logger.warn("Failed to fill up employee value for encounter")
        encounter
    end
  end

  def get(patient_id_hash, id) do
    with %{"encounters" => %{^id => encounter}} <-
           Mongo.find_one(@patient_collection, %{
             "_id" => patient_id_hash,
             "encounters.#{id}" => %{"$exists" => true}
           }) do
      {:ok, Encounter.create(encounter)}
    else
      _ ->
        nil
    end
  end

  def list(%{"patient_id_hash" => patient_id_hash} = params) do
    pipeline =
      [
        %{"$match" => %{"_id" => patient_id_hash}},
        %{"$project" => %{"encounters" => %{"$objectToArray" => "$encounters"}}},
        %{"$unwind" => "$encounters"}
      ]
      |> add_search_pipeline(params)
      |> Enum.concat([
        %{"$project" => %{"encounter" => "$encounters.v"}},
        %{"$replaceRoot" => %{"newRoot" => "$encounter"}},
        %{"$sort" => %{"inserted_at" => -1}}
      ])

    with %Page{entries: encounters} = paging <-
           Paging.paginate(:aggregate, @patient_collection, pipeline, Map.take(params, ~w(page page_size))) do
      {:ok, %Page{paging | entries: Enum.map(encounters, &Encounter.create/1)}}
    end
  end

  defp add_search_pipeline(pipeline, params) do
    path = "encounters.v"
    episode_id = Maybe.map(params["episode_id"], &Mongo.string_to_uuid(&1))
    date_from = get_filter_date(:from, params["date_from"])
    date_to = get_filter_date(:to, params["date_to"])

    search_pipeline =
      %{"$match" => %{}}
      |> Search.add_param(episode_id, ["$match", "#{path}.episode.identifier.value"])
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

  defp get_filter_date(:from, nil), do: nil

  defp get_filter_date(:from, date) do
    case DateTime.from_iso8601("#{date} 00:00:00Z") do
      {:ok, date_time, _} -> date_time
      _ -> nil
    end
  end

  defp get_filter_date(:to, nil), do: nil

  defp get_filter_date(:to, date) do
    with {:ok, date} <- Date.from_iso8601(date),
         to_date <- date |> Date.add(1) |> Date.to_string(),
         {:ok, date_time, _} <- DateTime.from_iso8601("#{to_date} 00:00:00Z") do
      date_time
    else
      _ -> nil
    end
  end

  defp add_search_param(nil, _, _, _), do: []
  defp add_search_param(pipeline, nil, _, _) when is_list(pipeline), do: pipeline

  defp add_search_param(pipeline, value, path, operator) when is_list(pipeline) do
    pipeline ++
      [
        %{
          "$project" => %{
            "encounters" => %{
              "$filter" => %{
                "input" => "$encounters",
                "as" => "item",
                "cond" => %{operator => ["$$item.v.#{path}", value]}
              }
            }
          }
        }
      ]
  end
end
