defmodule Core.Patients.Episodes do
  @moduledoc false

  alias Core.Mongo
  alias Core.Patient
  require Logger

  @collection Patient.metadata().collection

  def get(patient_id, id) do
    with %{"episodes" => %{^id => episode}} <-
           Mongo.find_one(@collection, %{"_id" => patient_id}, "episodes.#{id}": true) do
      {:ok, episode}
    else
      _ ->
        nil
    end
  end

  def list(%{"patient_id" => patient_id} = params) do
    # TODO: filter by code
    pipeline = [
      %{"$match" => %{"_id" => patient_id}},
      %{"$project" => %{"episodes" => %{"$objectToArray" => "$episodes"}}},
      %{"$unwind" => "$episodes"},
      %{
        "$project" => %{"_id" => "$episodes.k", "episode" => "$episodes.v"}
      },
      %{"$sort" => %{"episode.inserted_at" => -1}}
    ]

    [page_number: page_number, limit: page_size, offset: offset] = page_ops(params)
    paging_pipeline = pipeline ++ [%{"$skip" => offset}, %{"$limit" => page_size}]
    count_pipeline = pipeline ++ [%{"$count" => "total"}]

    episodes =
      paging_pipeline
      |> list_episodes()
      |> Enum.map(&Map.get(&1, "episode"))

    count = list_episodes(count_pipeline)
    {:ok, episodes, paging(page_number, page_size, count)}
  end

  defp list_episodes(pipeline) do
    @collection
    |> Mongo.aggregate(pipeline)
    |> Enum.to_list()
  end

  defp page_ops(params) do
    page_number = Map.get(params, "page_number", 1)
    page_size = Map.get(params, "page_size", 100)
    offset = if page_number > 0, do: (page_number - 1) * page_size, else: 0
    [page_number: page_number, limit: page_size, offset: offset]
  end

  defp paging(page, page_size, total) do
    total =
      case total do
        [%{"total" => total}] -> total
        _ -> 0
      end

    total_pages = trunc(Float.ceil(total / page_size))

    %{
      "total_pages" => total_pages,
      "total_entries" => total,
      "page_size" => page_size,
      "page_number" => page
    }
  end
end
