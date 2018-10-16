defmodule Core.Patients.Episodes do
  @moduledoc false

  use Core.Schema
  alias Core.Episode
  alias Core.Mongo
  alias Core.Paging
  alias Core.Patient
  alias Scrivener.Page
  require Logger

  @collection Patient.metadata().collection

  def get(patient_id_hash, id) do
    with %{"episodes" => %{^id => episode}} <-
           Mongo.find_one(@collection, %{
             "_id" => patient_id_hash,
             "episodes.#{id}" => %{"$exists" => true}
           }) do
      {:ok, episode}
    else
      _ ->
        nil
    end
  end

  def list(%{"patient_id_hash" => patient_id_hash} = params) do
    pipeline =
      [
        %{"$match" => %{"_id" => patient_id_hash}},
        %{"$project" => %{"episodes" => %{"$objectToArray" => "$episodes"}}},
        %{"$unwind" => "$episodes"},
        %{"$project" => %{"episode" => "$episodes.v"}},
        %{"$replaceRoot" => %{"newRoot" => "$episode"}}
      ]
      |> search_condition(params)
      |> Enum.concat([%{"$sort" => %{"inserted_at" => -1}}])

    with %Page{} = paging <-
           Paging.paginate(
             :aggregate,
             @collection,
             pipeline,
             Map.take(params, ~w(page page_size))
           ) do
      paging
    end
  end

  defp search_condition(pipeline, params) do
    pipeline
    |> add_period_criterias(params)
    |> search_code(Map.get(params, "code"))
  end

  defp add_period_criterias(pipeline, %{"period_from" => date_from, "period_to" => date_to}) do
    from = create_datetime(date_from)
    to = create_datetime(date_to)

    pipeline ++
      [
        %{
          "$addFields" => %{
            "period_match" => %{
              "$and" => [
                %{"$lte" => ["$period.start", to]},
                %{
                  "$or" => [
                    %{"$gte" => ["$period.end", from]},
                    %{"$eq" => ["$period.end", nil]}
                  ]
                }
              ]
            }
          }
        },
        %{"$match" => %{"period_match" => true}},
        %{"$project" => %{"period_match" => 0}}
      ]
  end

  defp add_period_criterias(pipeline, %{"period_from" => date}) do
    from = create_datetime(date)

    pipeline ++
      [
        %{
          "$addFields" => %{
            "period_match" => %{
              "$or" => [
                %{"$gte" => ["$period.end", from]},
                %{"$eq" => ["$period.end", nil]}
              ]
            }
          }
        },
        %{"$match" => %{"period_match" => true}},
        %{"$project" => %{"period_match" => 0}}
      ]
  end

  defp add_period_criterias(pipeline, %{"period_to" => date}) do
    to = create_datetime(date)

    pipeline ++
      [
        %{
          "$addFields" => %{
            "period_match" => %{"$lte" => ["$period.start", to]}
          }
        },
        %{"$match" => %{"period_match" => true}},
        %{"$project" => %{"period_match" => 0}}
      ]
  end

  defp add_period_criterias(pipeline, _), do: pipeline

  defp search_code(pipeline, nil), do: pipeline

  defp search_code(pipeline, _code) do
    pipeline ++
      [
        # TODO: implement search by code
      ]
  end

  def fill_up_episode_care_manager(%Episode{care_manager: care_manager} = episode) do
    with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{care_manager.identifier.value}") do
      first_name = get_in(employee, ["party", "first_name"])
      second_name = get_in(employee, ["party", "second_name"])
      last_name = get_in(employee, ["party", "last_name"])

      %{
        episode
        | care_manager: %{
            care_manager
            | display_value: "#{first_name} #{second_name} #{last_name}"
          }
      }
    else
      _ ->
        Logger.warn("Failed to fill up employee value for episode")
        episode
    end
  end

  def fill_up_episode_managing_organization(%Episode{managing_organization: managing_organization} = episode) do
    with [{_, legal_entity}] <- :ets.lookup(:message_cache, "legal_entity_#{managing_organization.identifier.value}") do
      %{
        episode
        | managing_organization: %{
            managing_organization
            | display_value: Map.get(legal_entity, "public_name")
          }
      }
    else
      _ ->
        Logger.warn("Failed to fill up legal_entity value for episode")
        episode
    end
  end
end
