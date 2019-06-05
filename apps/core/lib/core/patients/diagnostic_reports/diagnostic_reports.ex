defmodule Core.Patients.DiagnosticReports do
  @moduledoc false

  alias Core.DiagnosticReport
  alias Core.Maybe
  alias Core.Mongo
  alias Core.Paging
  alias Core.Patient
  alias Core.Patients.Encounters
  alias Core.Search
  alias Core.Validators.JsonSchema
  alias Scrivener.Page
  require Logger

  @collection Patient.collection()

  def get_by_id(patient_id_hash, id) do
    with %{"diagnostic_reports" => %{^id => diagnostic_report}} <-
           Mongo.find_one(
             @collection,
             %{
               "_id" => patient_id_hash,
               "diagnostic_reports.#{id}" => %{"$exists" => true}
             },
             projection: ["diagnostic_reports.#{id}": true]
           ) do
      {:ok, DiagnosticReport.create(diagnostic_report)}
    else
      _ ->
        nil
    end
  end

  def get_summary(patient_id_hash, id) do
    with %{"diagnostic_reports" => %{^id => diagnostic_report}} <-
           Mongo.find_one(@collection, %{
             "_id" => patient_id_hash,
             "diagnostic_reports.#{id}" => %{"$exists" => true},
             "diagnostic_reports.#{id}.conclusion_code.coding.code" => %{
               "$in" => Confex.fetch_env!(:core, :summary)[:diagnostic_reports_whitelist]
             }
           }) do
      {:ok, DiagnosticReport.create(diagnostic_report)}
    else
      _ ->
        nil
    end
  end

  def list(%{"patient_id_hash" => patient_id_hash} = params, schema \\ :diagnostic_report_request) do
    with :ok <-
           JsonSchema.validate(
             schema,
             Map.drop(params, ~w(page page_size patient_id patient_id_hash))
           ) do
      pipeline =
        [
          %{"$match" => %{"_id" => patient_id_hash}},
          %{
            "$project" => %{"diagnostic_reports" => %{"$objectToArray" => "$diagnostic_reports"}}
          },
          %{"$unwind" => "$diagnostic_reports"}
        ]
        |> add_search_pipeline(patient_id_hash, params, schema)
        |> Enum.concat([
          %{"$project" => %{"diagnostic_report" => "$diagnostic_reports.v"}},
          %{"$replaceRoot" => %{"newRoot" => "$diagnostic_report"}},
          %{"$sort" => %{"inserted_at" => -1}}
        ])

      with %Page{entries: diagnostic_reports} = paging <-
             Paging.paginate(
               :aggregate,
               @collection,
               pipeline,
               Map.take(params, ~w(page page_size))
             ) do
        {:ok, %Page{paging | entries: Enum.map(diagnostic_reports, &DiagnosticReport.create/1)}}
      end
    end
  end

  defp add_search_pipeline(pipeline, patient_id_hash, params, schema) do
    path = "diagnostic_reports.v"
    encounter_id = Maybe.map(params["encounter_id"], &Mongo.string_to_uuid(&1))
    issued_from = Search.get_filter_date(:from, params["issued_from"])
    issued_to = Search.get_filter_date(:to, params["issued_to"])

    code = if params["code"], do: Mongo.string_to_uuid(params["code"])

    context_episode_id = if params["context_episode_id"], do: Mongo.string_to_uuid(params["context_episode_id"])

    origin_episode_id = if params["origin_episode_id"], do: Mongo.string_to_uuid(params["origin_episode_id"])

    encounter_ids = if !is_nil(context_episode_id), do: get_encounter_ids(patient_id_hash, context_episode_id)

    based_on = if params["based_on"], do: Mongo.string_to_uuid(params["based_on"])

    search_pipeline =
      %{"$match" => %{}}
      |> Search.add_param(code, ["$match", "#{path}.code.identifier.value"])
      |> Search.add_param(encounter_id, ["$match", "#{path}.encounter.identifier.value"])
      |> add_search_param(encounter_ids, ["$match", "#{path}.encounter.identifier.value"], "$in")
      |> Search.add_param(issued_from, ["$match", "#{path}.issued"], "$gte")
      |> Search.add_param(issued_to, ["$match", "#{path}.issued"], "$lt")
      |> Search.add_param(origin_episode_id, ["$match", "#{path}.origin_episode.identifier.value"])
      |> Search.add_param(based_on, ["$match", "#{path}.based_on.identifier.value"])

    search_pipeline =
      if schema == :diagnostic_report_summary do
        Search.add_param(
          search_pipeline,
          Confex.fetch_env!(:core, :summary)[:diagnostic_reports_whitelist],
          ["$match", "#{path}.conclusion_code.coding.code"],
          "$in"
        )
      else
        search_pipeline
      end

    search_pipeline
    |> Map.get("$match", %{})
    |> Map.keys()
    |> case do
      [] -> pipeline
      _ -> pipeline ++ [search_pipeline]
    end
  end

  def get_encounter_ids(patient_id_hash, episode_id) do
    patient_id_hash
    |> Encounters.get_episode_encounters(episode_id)
    |> Enum.map(& &1["encounter_id"])
    |> Enum.uniq()
  end

  defp add_search_param(search_params, nil, _path, _operator), do: search_params

  defp add_search_param(search_params, value, path, operator) do
    if get_in(search_params, path) == nil do
      put_in(search_params, path, %{operator => value})
    else
      update_in(search_params, path, &Map.merge(&1, %{operator => value}))
    end
  end

  def get_by_encounter_id(patient_id_hash, %BSON.Binary{} = encounter_id) do
    @collection
    |> Mongo.aggregate([
      %{"$match" => %{"_id" => patient_id_hash}},
      %{"$project" => %{"diagnostic_reports" => %{"$objectToArray" => "$diagnostic_reports"}}},
      %{"$unwind" => "$diagnostic_reports"},
      %{"$match" => %{"diagnostic_reports.v.encounter.identifier.value" => encounter_id}},
      %{"$replaceRoot" => %{"newRoot" => "$diagnostic_reports.v"}}
    ])
    |> Enum.map(&DiagnosticReport.create/1)
  end
end
