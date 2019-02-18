defmodule Core.Patients.Episodes do
  @moduledoc false

  use Core.Schema
  alias Core.Episode
  alias Core.Mongo
  alias Core.Paging
  alias Core.Patient
  alias Core.Validators.JsonSchema
  alias Scrivener.Page
  require Logger

  @collection Patient.metadata().collection

  def get_by_id(patient_id_hash, id) do
    with %{"episodes" => %{^id => episode}} <-
           Mongo.find_one(@collection, %{
             "_id" => patient_id_hash,
             "episodes.#{id}" => %{"$exists" => true}
           }) do
      {:ok, Episode.create(episode)}
    else
      _ ->
        nil
    end
  end

  def list(%{"patient_id_hash" => patient_id_hash} = params, schema \\ :episode_get) do
    with :ok <- JsonSchema.validate(schema, Map.drop(params, ~w(page page_size patient_id patient_id_hash))) do
      pipeline =
        [
          %{"$match" => %{"_id" => patient_id_hash}},
          %{"$project" => %{"episodes" => %{"$objectToArray" => "$episodes"}}},
          %{"$unwind" => "$episodes"},
          %{"$replaceRoot" => %{"newRoot" => "$episodes.v"}}
        ]
        |> search_condition(params)
        |> Enum.concat([%{"$sort" => %{"inserted_at" => -1}}])

      with %Page{entries: episodes} = paging <-
             Paging.paginate(:aggregate, @collection, pipeline, Map.take(params, ~w(page page_size))) do
        {:ok, %Page{paging | entries: Enum.map(episodes, &Episode.create/1)}}
      end
    end
  end

  defp search_condition(pipeline, params) do
    pipeline
    |> search_period_criterias(params)
    |> search_code(Map.get(params, "code"))
    |> search_service_request_id(Map.get(params, "service_request_id"))
  end

  defp search_period_criterias(pipeline, %{"period_from" => date_from, "period_to" => date_to}) do
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
                    %{"$not" => ["$period.end"]}
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

  defp search_period_criterias(pipeline, %{"period_from" => date}) do
    from = create_datetime(date)

    pipeline ++
      [
        %{
          "$addFields" => %{
            "period_match" => %{
              "$or" => [
                %{"$gte" => ["$period.end", from]},
                %{"$not" => ["$period.end"]}
              ]
            }
          }
        },
        %{"$match" => %{"period_match" => true}},
        %{"$project" => %{"period_match" => 0}}
      ]
  end

  defp search_period_criterias(pipeline, %{"period_to" => date}) do
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

  defp search_period_criterias(pipeline, _), do: pipeline

  defp search_code(pipeline, nil), do: pipeline

  defp search_code(pipeline, code) do
    pipeline ++
      [
        %{
          "$match" => %{
            "current_diagnoses.code.coding.code" => code
          }
        }
      ]
  end

  defp search_service_request_id(pipeline, nil), do: pipeline

  defp search_service_request_id(pipeline, service_request_id) do
    pipeline ++
      [
        %{
          "$match" => %{
            "referral_requests" => %{
              "$elemMatch" => %{
                "identifier.type.coding.code" => "service_request",
                "identifier.value" => Mongo.string_to_uuid(service_request_id)
              }
            }
          }
        }
      ]
  end
end
