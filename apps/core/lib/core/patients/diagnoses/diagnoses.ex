defmodule Core.Diagnoses do
  @moduledoc false

  alias Core.Diagnosis
  alias Core.Episode
  alias Core.Paging
  alias Core.Patient
  alias Scrivener.Page
  require Logger

  @collection Patient.metadata().collection

  def list_active_diagnoses(params) do
    paging_params = Map.take(params, ~w(page page_size))

    with [_ | _] = pipeline <- search_diagnoses_summary(params),
         %Page{entries: diagnoses} = page <- Paging.paginate(:aggregate, @collection, pipeline, paging_params) do
      {:ok, %Page{page | entries: Enum.map(diagnoses, &Diagnosis.create/1)}}
    else
      _ -> {:ok, Paging.create()}
    end
  end

  defp search_diagnoses_summary(%{"patient_id_hash" => patient_id_hash} = params) do
    codes = Confex.fetch_env!(:core, :summary)[:conditions_whitelist]

    [
      %{"$match" => %{"_id" => patient_id_hash}},
      %{"$project" => %{"episodes" => %{"$objectToArray" => "$episodes"}}},
      %{"$unwind" => "$episodes"},
      %{"$replaceRoot" => %{"newRoot" => "$episodes.v"}},
      %{"$match" => %{"status" => Episode.status(:active)}},
      %{"$project" => %{"current_diagnoses" => "$current_diagnoses"}},
      %{"$match" => %{"current_diagnoses" => %{"$ne" => nil}}},
      %{"$unwind" => "$current_diagnoses"},
      %{"$replaceRoot" => %{"newRoot" => "$current_diagnoses"}},
      %{"$match" => %{"code.coding.code" => %{"$in" => codes}}}
    ]
    |> add_code_param(params)
    |> Enum.concat([%{"$sort" => %{"inserted_at" => -1}}])
  end

  defp add_code_param(pipeline, %{"code" => code}) when is_binary(code) do
    Enum.concat(pipeline, [%{"$match" => %{"code.coding.code" => code}}])
  end

  defp add_code_param(pipeline, _), do: pipeline
end
