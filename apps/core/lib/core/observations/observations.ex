defmodule Core.Observations do
  @moduledoc false

  alias Core.Maybe
  alias Core.Mongo
  alias Core.Observation
  alias Core.Paging
  alias Core.Patients
  alias Core.Patients.Encounters
  alias Core.Reference
  alias Core.Search
  alias Core.Source
  alias Scrivener.Page

  require Logger

  @observation_collection Observation.metadata().collection

  def get(patient_id, id) do
    @observation_collection
    |> Mongo.find_one(%{
      "_id" => Mongo.string_to_uuid(id),
      "patient_id" => Patients.get_pk_hash(patient_id)
    })
    |> case do
      %{} = observation -> {:ok, Observation.create(observation)}
      _ -> nil
    end
  end

  def get_by_encounter_id(patient_id, encounter_id) do
    @observation_collection
    |> Mongo.find(%{"patient_id" => patient_id, "context.identifier.value" => encounter_id})
    |> Enum.map(&Observation.create/1)
  end

  def list(params) do
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
        patient_id: Patients.get_pk_hash(observation.patient_id),
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

  defp search_observations_pipe(%{"patient_id" => patient_id} = params) do
    code = params["code"]
    issued_from = filter_date(params["issued_from"])
    issued_to = filter_date(params["issued_to"], true)

    episode_id = Maybe.map(params["episode_id"], &Mongo.string_to_uuid(&1))
    encounter_ids = get_encounter_ids(patient_id, episode_id)

    if episode_id != nil and encounter_ids == [] do
      []
    else
      encounter_ids =
        Maybe.map(
          params["encounter_id"],
          &Enum.uniq([Mongo.string_to_uuid(&1) | encounter_ids]),
          encounter_ids
        )

      %{"$match" => %{"patient_id" => Patients.get_pk_hash(patient_id)}}
      |> Search.add_param(code, ["$match", "code.coding.0.code"])
      |> Search.add_param(encounter_ids, ["$match", "context.identifier.value"], "$in")
      |> Search.add_param(issued_from, ["$match", "issued"], "$gte")
      |> Search.add_param(issued_to, ["$match", "issued"], "$lte")
      |> List.wrap()
      |> Enum.concat([%{"$sort" => %{"inserted_at" => -1}}])
    end
  end

  defp filter_date(date, end_day_time? \\ false) do
    time = (end_day_time? && "23:59:59") || "00:00:00"

    case DateTime.from_iso8601("#{date} #{time}Z") do
      {:ok, date_time, _} -> date_time
      _ -> nil
    end
  end

  def get_encounter_ids(_patient_id, nil), do: []

  def get_encounter_ids(patient_id, episode_id) do
    patient_id
    |> Encounters.get_episode_encounters(episode_id)
    |> Enum.map(& &1["encounter_id"])
  end

  defp fill_up_observation_performer(%Reference{identifier: identifier}) do
    with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{identifier.value}") do
      first_name = get_in(employee, ["party", "first_name"])
      second_name = get_in(employee, ["party", "second_name"])
      last_name = get_in(employee, ["party", "last_name"])

      "#{first_name} #{second_name} #{last_name}"
    else
      _ ->
        Logger.warn("Failed to fill up employee value for observation")
        nil
    end
  end
end
