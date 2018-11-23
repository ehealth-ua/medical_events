defmodule Core.Observations do
  @moduledoc false

  alias Core.Maybe
  alias Core.Mongo
  alias Core.Observation
  alias Core.Paging
  alias Core.Patients.Encounters
  alias Core.Reference
  alias Core.Search
  alias Core.Source
  alias Core.Validators.JsonSchema
  alias Scrivener.Page

  require Logger

  @observation_collection Observation.metadata().collection

  def get(patient_id_hash, id) do
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

  def get_by_encounter_id(patient_id_hash, encounter_id) do
    @observation_collection
    |> Mongo.find(%{"patient_id" => patient_id_hash, "context.identifier.value" => encounter_id})
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
    context = observation.context

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

    based_on =
      case observation.based_on do
        nil ->
          nil

        _ ->
          Enum.map(observation.based_on, fn item ->
            %{
              item
              | identifier: %{
                  item.identifier
                  | value: Mongo.string_to_uuid(item.identifier.value)
                }
            }
          end)
      end

    %{
      observation
      | _id: Mongo.string_to_uuid(observation._id),
        inserted_by: Mongo.string_to_uuid(observation.inserted_by),
        updated_by: Mongo.string_to_uuid(observation.updated_by),
        context: %{
          context
          | identifier: %{
              context.identifier
              | value: Mongo.string_to_uuid(context.identifier.value)
            }
        },
        source: source,
        based_on: based_on
    }
  end

  defp search_observations_pipe(%{"patient_id_hash" => patient_id_hash} = params) do
    code = params["code"]
    issued_from = filter_date(params["issued_from"])
    issued_to = filter_date(params["issued_to"], true)

    episode_id = Maybe.map(params["episode_id"], &Mongo.string_to_uuid(&1))
    encounter_ids = get_encounter_ids(patient_id_hash, episode_id)

    if episode_id != nil and encounter_ids == [] do
      []
    else
      encounter_ids =
        Maybe.map(
          params["encounter_id"],
          &Enum.uniq([Mongo.string_to_uuid(&1) | encounter_ids]),
          encounter_ids
        )

      %{"$match" => %{"patient_id" => patient_id_hash}}
      |> Search.add_param(code, ["$match", "code.coding.0.code"])
      |> Search.add_param(encounter_ids, ["$match", "context.identifier.value"], "$in")
      |> Search.add_param(issued_from, ["$match", "issued"], "$gte")
      |> Search.add_param(issued_to, ["$match", "issued"], "$lte")
      |> List.wrap()
      |> Enum.concat([%{"$sort" => %{"inserted_at" => -1}}])
    end
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

  def get_encounter_ids(_patient_id_hash, nil), do: []

  def get_encounter_ids(patient_id_hash, episode_id) do
    patient_id_hash
    |> Encounters.get_episode_encounters(episode_id)
    |> Enum.map(& &1["encounter_id"])
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
end
