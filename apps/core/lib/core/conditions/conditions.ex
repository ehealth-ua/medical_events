defmodule Core.Conditions do
  @moduledoc false

  alias Core.Condition
  alias Core.Evidence
  alias Core.Mongo
  alias Core.Paging
  alias Core.Patients.Encounters
  alias Core.Reference
  alias Core.Source
  alias Scrivener.Page
  require Logger

  @condition_collection Condition.metadata().collection

  def get(patient_id, id) do
    @condition_collection
    |> Mongo.find_one(%{"_id" => Mongo.string_to_uuid(id), "patient_id" => patient_id})
    |> case do
      %{} = condition -> {:ok, Condition.create(condition)}
      _ -> nil
    end
  end

  def list(params) do
    pipeline = search_conditions_pipe(params)
    paging_params = Map.take(params, ~w(page page_size))

    with %Page{entries: conditions} = page <-
           Paging.paginate(:aggregate, @condition_collection, pipeline, paging_params) do
      {:ok, %Page{page | entries: Enum.map(conditions, &Condition.create/1)}}
    end
  end

  def create(%Condition{} = condition) do
    context = condition.context

    source =
      case condition.source do
        %Source{type: "report_origin"} = source ->
          source

        %Source{value: value} = source ->
          %{
            source
            | value: %{
                value
                | identifier: %{value.identifier | value: Mongo.string_to_uuid(value.identifier.value)},
                  display_value: fill_up_condition_asserter(value)
              }
          }
      end

    evidences = create_evidences(condition)

    %{
      condition
      | _id: Mongo.string_to_uuid(condition._id),
        inserted_by: Mongo.string_to_uuid(condition.inserted_by),
        updated_by: Mongo.string_to_uuid(condition.updated_by),
        context: %{
          context
          | identifier: %{context.identifier | value: Mongo.string_to_uuid(context.identifier.value)}
        },
        source: source,
        evidences: evidences
    }
  end

  defp search_conditions_pipe(%{"patient_id" => patient_id} = params) do
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
    patient_id
    |> Encounters.get_episode_encounters(episode_id)
    |> Enum.map(& &1["encounter_id"])
  end

  defp add_search_param(search_params, value, path, operator \\ "$eq")
  defp add_search_param(search_params, nil, _path, _operator), do: search_params
  defp add_search_param(search_params, [], _path, _operator), do: search_params
  defp add_search_param(search_params, value, path, operator), do: put_in(search_params, path, %{operator => value})

  defp fill_up_condition_asserter(%Reference{identifier: identifier}) do
    with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{identifier.value}") do
      first_name = get_in(employee, ["party", "first_name"])
      second_name = get_in(employee, ["party", "second_name"])
      last_name = get_in(employee, ["party", "last_name"])

      "#{first_name} #{second_name} #{last_name}"
    else
      _ ->
        Logger.warn("Failed to fill up employee value for condition")
        nil
    end
  end

  defp create_evidences(%Condition{evidences: nil}), do: nil

  defp create_evidences(%Condition{evidences: evidences}) do
    Enum.map(evidences, fn
      %Evidence{details: nil} = evidence ->
        evidence

      %Evidence{details: details} = evidence ->
        details =
          Enum.map(details, fn detail ->
            %{detail | identifier: %{detail.identifier | value: Mongo.string_to_uuid(detail.identifier.value)}}
          end)

        %{evidence | details: details}
    end)
  end
end
