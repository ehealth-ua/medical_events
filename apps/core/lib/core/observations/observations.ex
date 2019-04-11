defmodule Core.Observations do
  @moduledoc false

  alias Core.Maybe
  alias Core.Mongo
  alias Core.Observation
  alias Core.Paging
  alias Core.Reference
  alias Core.Search
  alias Core.Source
  alias Core.Validators.JsonSchema
  alias Scrivener.Page

  require Logger

  @observation_collection Observation.metadata().collection

  def get_by_id(patient_id_hash, id) do
    @observation_collection
    |> Mongo.find_one(%{
      "_id" => Mongo.string_to_uuid(id),
      "patient_id" => patient_id_hash
    })
    |> case do
      %{} = observation -> {:ok, Observation.create(observation)}
      _ -> nil
    end
  end

  def get_by_id_episode_id(patient_id_hash, id, episode_id) do
    @observation_collection
    |> Mongo.find_one(%{
      "_id" => Mongo.string_to_uuid(id),
      "patient_id" => patient_id_hash,
      "context_episode_id" => Mongo.string_to_uuid(episode_id)
    })
    |> case do
      %{} = observation -> {:ok, Observation.create(observation)}
      _ -> nil
    end
  end

  def get_summary(patient_id_hash, id) do
    @observation_collection
    |> Mongo.find_one(%{
      "_id" => Mongo.string_to_uuid(id),
      "patient_id" => patient_id_hash,
      "code.coding.code" => %{"$in" => Confex.fetch_env!(:core, :summary)[:observations_whitelist]}
    })
    |> case do
      %{} = observation -> {:ok, Observation.create(observation)}
      _ -> nil
    end
  end

  def get_by_encounter_id(patient_id_hash, %BSON.Binary{} = encounter_id) do
    @observation_collection
    |> Mongo.find(%{"patient_id" => patient_id_hash, "context.identifier.value" => encounter_id})
    |> Enum.map(&Observation.create/1)
  end

  def get_by_diagnostic_report_id(patient_id_hash, %BSON.Binary{} = diagnostic_report_id) do
    @observation_collection
    |> Mongo.find(%{"patient_id" => patient_id_hash, "diagnostic_report.identifier.value" => diagnostic_report_id})
    |> Enum.map(&Observation.create/1)
  end

  def list(params) do
    json_params = Map.drop(params, ~w(page page_size patient_id patient_id_hash))

    with :ok <- JsonSchema.validate(:observation_request, json_params) do
      paging_params = Map.take(params, ["page", "page_size"])

      with [_ | _] = pipeline <- search_observations_pipe(params),
           %Page{entries: observations} = page <-
             Paging.paginate(
               :aggregate,
               @observation_collection,
               pipeline,
               paging_params
             ) do
        {:ok, %Page{page | entries: Enum.map(observations, &Observation.create/1)}}
      else
        _ -> {:ok, Paging.create()}
      end
    end
  end

  def summary(params) do
    json_params = Map.drop(params, ~w(page page_size patient_id patient_id_hash))

    with :ok <- JsonSchema.validate(:observation_summary, json_params) do
      paging_params = Map.take(params, ["page", "page_size"])

      with [_ | _] = pipeline <- search_observations_summary(params),
           %Page{entries: observations} = page <-
             Paging.paginate(
               :aggregate,
               @observation_collection,
               pipeline,
               paging_params
             ) do
        {:ok, %Page{page | entries: Enum.map(observations, &Observation.create/1)}}
      else
        _ -> {:ok, Paging.create()}
      end
    end
  end

  def create(%Observation{} = observation) do
    source =
      case observation.source do
        %Source{type: "report_origin"} = source ->
          source

        %Source{value: value} = source ->
          %{
            source
            | value: %{
                value
                | identifier: %{
                    value.identifier
                    | value: Mongo.string_to_uuid(value.identifier.value)
                  },
                  display_value: fill_up_observation_performer(value)
              }
          }
      end

    based_on = update_reference_uuid(observation.based_on)
    context = update_reference_uuid(observation.context)
    diagnostic_report = update_reference_uuid(observation.diagnostic_report)

    context_episode_uuid =
      case observation.context_episode_id do
        nil -> nil
        _ -> Mongo.string_to_uuid(observation.context_episode_id)
      end

    %{
      observation
      | _id: Mongo.string_to_uuid(observation._id),
        inserted_by: Mongo.string_to_uuid(observation.inserted_by),
        updated_by: Mongo.string_to_uuid(observation.updated_by),
        context_episode_id: context_episode_uuid,
        context: context,
        diagnostic_report: diagnostic_report,
        source: source,
        based_on: based_on
    }
  end

  defp search_observations_pipe(%{"patient_id_hash" => patient_id_hash} = params) do
    code = params["code"]
    issued_from = filter_date(params["issued_from"])
    issued_to = filter_date(params["issued_to"], true)
    episode_id = Maybe.map(params["episode_id"], &Mongo.string_to_uuid(&1))
    encounter_id = Maybe.map(params["encounter_id"], &Mongo.string_to_uuid(&1))

    %{"$match" => %{"patient_id" => patient_id_hash}}
    |> Search.add_param(code, ["$match", "code.coding.0.code"])
    |> Search.add_param(encounter_id, ["$match", "context.identifier.value"])
    |> Search.add_param(episode_id, ["$match", "context_episode_id"])
    |> Search.add_param(issued_from, ["$match", "issued"], "$gte")
    |> Search.add_param(issued_to, ["$match", "issued"], "$lte")
    |> List.wrap()
    |> Enum.concat([%{"$sort" => %{"inserted_at" => -1}}])
  end

  defp search_observations_summary(%{"patient_id_hash" => patient_id_hash} = params) do
    code = params["code"]
    codes = Confex.fetch_env!(:core, :summary)[:observations_whitelist]
    issued_from = filter_date(params["issued_from"])
    issued_to = filter_date(params["issued_to"], true)

    %{"$match" => %{"patient_id" => patient_id_hash}}
    |> Search.add_param(code, ["$match", "code.coding.0.code"])
    |> Search.add_param(codes, ["$match", "code.coding.0.code"], "$in")
    |> Search.add_param(issued_from, ["$match", "issued"], "$gte")
    |> Search.add_param(issued_to, ["$match", "issued"], "$lte")
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

  defp fill_up_observation_performer(%Reference{identifier: identifier}) do
    with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{identifier.value}") do
      first_name = employee.party.first_name
      second_name = employee.party.second_name
      last_name = employee.party.last_name

      "#{first_name} #{second_name} #{last_name}"
    else
      _ ->
        Logger.warn("Failed to fill up employee value for observation")
        nil
    end
  end

  defp update_reference_uuid(nil), do: nil

  defp update_reference_uuid(value) when is_list(value), do: Enum.map(value, &update_reference_uuid/1)

  defp update_reference_uuid(value) do
    %{
      value
      | identifier: %{
          value.identifier
          | value: Mongo.string_to_uuid(value.identifier.value)
        }
    }
  end
end
