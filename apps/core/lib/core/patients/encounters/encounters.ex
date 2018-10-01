defmodule Core.Patients.Encounters do
  @moduledoc false

  alias Core.Encounter
  alias Core.Mongo
  alias Core.Paging
  alias Core.Patient
  alias Core.Patients
  alias Scrivener.Page
  require Logger

  @patient_collection Patient.metadata().collection

  def get_episode_encounters(
        patient_id,
        %BSON.Binary{} = episode_id,
        project \\ %{
          "episode_id" => "$encounters.v.episode.identifier.value",
          "encounter_id" => "$encounters.v.id"
        }
      ) do
    pipeline = [
      %{
        "$match" => %{
          "_id" => Patients.get_pk_hash(patient_id)
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
      first_name = get_in(employee, ["party", "first_name"])
      second_name = get_in(employee, ["party", "second_name"])
      last_name = get_in(employee, ["party", "last_name"])

      %{encounter | performer: %{performer | display_value: "#{first_name} #{second_name} #{last_name}"}}
    else
      _ ->
        Logger.warn("Failed to fill up employee value for encounter")
        encounter
    end
  end

  def get(patient_id, id) do
    with %{"encounters" => %{^id => encounter}} <-
           Mongo.find_one(@patient_collection, %{
             "_id" => Patients.get_pk_hash(patient_id),
             "encounters.#{id}" => %{"$exists" => true}
           }) do
      {:ok, Encounter.create(encounter)}
    else
      _ ->
        nil
    end
  end

  def list(%{"patient_id" => patient_id} = params) do
    episode_id = params["episode_id"]
    date_from = get_filter_date(:from, params["date_from"])
    date_to = get_filter_date(:to, params["date_to"])

    search_params_pipeline =
      []
      |> add_search_param(episode_id, "episode.identifier.value", "$eq")
      |> add_search_param(date_from, "date", "$gte")
      |> add_search_param(date_to, "date", "$lt")

    pipeline =
      [
        %{"$match" => %{"_id" => Patients.get_pk_hash(patient_id)}},
        %{"$project" => %{"encounters" => %{"$objectToArray" => "$encounters"}}}
      ] ++
        search_params_pipeline ++
        [
          %{"$unwind" => "$encounters"},
          %{"$project" => %{"encounter" => "$encounters.v"}},
          %{"$replaceRoot" => %{"newRoot" => "$encounter"}},
          %{"$sort" => %{"inserted_at" => -1}}
        ]

    with %Page{entries: encounters} = paging <-
           Paging.paginate(:aggregate, @patient_collection, pipeline, Map.take(params, ~w(page page_size))) do
      {:ok, %Page{paging | entries: Enum.map(encounters, &Encounter.create/1)}}
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

  defp add_search_param(_, _, _, _), do: []
end
