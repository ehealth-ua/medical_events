defmodule Core.Patients.Episodes do
  @moduledoc false

  alias Core.Mongo
  alias Core.Paging
  alias Core.Patient
  alias Scrivener.Page
  require Logger

  @collection Patient.metadata().collection

  def get(patient_id, id) do
    with %{"episodes" => %{^id => episode}} <-
           Mongo.find_one(@collection, %{"_id" => patient_id}, projection: ["episodes.#{id}": true]) do
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

    with %Page{} = paging <- Paging.paginate(:aggregate, @collection, pipeline, Map.take(params, ~w(page page_size))) do
      paging
    end
  end
end
