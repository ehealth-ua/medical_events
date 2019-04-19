defmodule Core.Patients.Encounters do
  @moduledoc false

  alias Core.Encounter
  alias Core.Maybe
  alias Core.Mongo
  alias Core.Paging
  alias Core.Patient
  alias Core.Search
  alias Core.Validators.JsonSchema
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

  def get_by_id_episode_id(patient_id_hash, id, episode_id) do
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
          "encounters.k" => id,
          "encounters.v.episode.identifier.value" => Mongo.string_to_uuid(episode_id)
        }
      },
      %{
        "$project" => %{"encounter" => "$encounters.v"}
      }
    ]

    with [%{"encounter" => encounter}] <- @patient_collection |> Mongo.aggregate(pipeline) |> Enum.to_list() do
      {:ok, Encounter.create(encounter)}
    else
      _ ->
        nil
    end
  end

  @spec get_status_by_id(binary(), binary()) :: nil | {:ok, binary()}
  def get_status_by_id(patient_id_hash, id) do
    with %{"encounters" => %{^id => %{"status" => status}}} <-
           Mongo.find_one(@patient_collection, %{"_id" => patient_id_hash},
             projection: ["encounters.#{id}.status": true]
           ) do
      {:ok, status}
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
      first_name = employee.party.first_name
      second_name = employee.party.second_name
      last_name = employee.party.last_name

      %{encounter | performer: %{performer | display_value: "#{first_name} #{second_name} #{last_name}"}}
    else
      _ ->
        Logger.warn("Failed to fill up employee value for encounter")
        encounter
    end
  end

  def fill_up_diagnoses_codes(%Encounter{diagnoses: diagnoses} = encounter) do
    diagnoses =
      Enum.map(diagnoses, fn diagnosis ->
        with [{_, condition}] <- :ets.lookup(:message_cache, "condition_#{diagnosis.condition.identifier.value}") do
          %{diagnosis | code: Map.get(condition, "code")}
        end
      end)

    %{encounter | diagnoses: diagnoses}
  end

  def list(%{"patient_id_hash" => patient_id_hash} = params) do
    search_params = Map.drop(params, ~w(page page_size))
    paging_params = Map.take(params, ~w(page page_size))

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

    with :ok <- JsonSchema.validate(:encounter_list, search_params),
         %Page{entries: encounters} = paging <-
           Paging.paginate(:aggregate, @patient_collection, pipeline, paging_params) do
      {:ok, %Page{paging | entries: Enum.map(encounters, &Encounter.create/1)}}
    end
  end

  defp add_search_pipeline(pipeline, params) do
    path = "encounters.v"
    episode_id = Maybe.map(params["episode_id"], &Mongo.string_to_uuid(&1))
    date_from = Search.get_filter_date(:from, params["date_from"])
    date_to = Search.get_filter_date(:to, params["date_to"])

    search_pipeline =
      %{"$match" => %{}}
      |> Search.add_param(episode_id, ["$match", "#{path}.episode.identifier.value"])
      |> Search.add_param(date_from, ["$match", "#{path}.date"], "$gte")
      |> Search.add_param(date_to, ["$match", "#{path}.date"], "$lt")
      |> search_by_incoming_referral(params["incoming_referral_id"])

    search_pipeline
    |> Map.get("$match", %{})
    |> Map.keys()
    |> case do
      [] -> pipeline
      _ -> pipeline ++ [search_pipeline]
    end
  end

  defp search_by_incoming_referral(pipeline, nil), do: pipeline

  defp search_by_incoming_referral(pipeline, incoming_referral) do
    put_in(pipeline, ["$match", "encounters.v.incoming_referrals"], %{
      "$elemMatch" => %{
        "identifier.type.coding.code" => "service_request",
        "identifier.value" => Mongo.string_to_uuid(incoming_referral)
      }
    })
  end
end
