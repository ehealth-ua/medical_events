defmodule Core.Patients.RiskAssessments do
  @moduledoc false

  alias Core.Maybe
  alias Core.Mongo
  alias Core.Paging
  alias Core.Patient
  alias Core.Patients.Encounters
  alias Core.Reference
  alias Core.RiskAssessment
  alias Core.Search
  alias Core.Validators.JsonSchema
  alias Scrivener.Page
  require Logger

  @collection Patient.metadata().collection

  def get_by_id(patient_id_hash, id) do
    with %{"risk_assessments" => %{^id => risk_assessment}} <-
           Mongo.find_one(@collection, %{
             "_id" => patient_id_hash,
             "risk_assessments.#{id}" => %{"$exists" => true}
           }) do
      {:ok, RiskAssessment.create(risk_assessment)}
    else
      _ ->
        nil
    end
  end

  def list(%{"patient_id_hash" => patient_id_hash} = params, schema \\ :risk_assessment_request) do
    with :ok <- JsonSchema.validate(schema, Map.drop(params, ~w(page page_size patient_id patient_id_hash))) do
      pipeline =
        [
          %{"$match" => %{"_id" => patient_id_hash}},
          %{"$project" => %{"risk_assessments" => %{"$objectToArray" => "$risk_assessments"}}},
          %{"$unwind" => "$risk_assessments"}
        ]
        |> add_search_pipeline(patient_id_hash, params)
        |> Enum.concat([
          %{"$project" => %{"risk_assessment" => "$risk_assessments.v"}},
          %{"$replaceRoot" => %{"newRoot" => "$risk_assessment"}},
          %{"$sort" => %{"inserted_at" => -1}}
        ])

      with %Page{entries: risk_assessments} = paging <-
             Paging.paginate(:aggregate, @collection, pipeline, Map.take(params, ~w(page page_size))) do
        {:ok, %Page{paging | entries: Enum.map(risk_assessments, &RiskAssessment.create/1)}}
      end
    end
  end

  defp add_search_pipeline(pipeline, patient_id_hash, params) do
    path = "risk_assessments.v"
    encounter_id = Maybe.map(params["encounter_id"], &Mongo.string_to_uuid(&1))
    asserted_date_from = Search.get_filter_date(:from, params["asserted_date_from"])
    asserted_date_to = Search.get_filter_date(:to, params["asserted_date_to"])

    episode_id = if params["episode_id"], do: Mongo.string_to_uuid(params["episode_id"]), else: nil
    encounter_ids = if is_nil(episode_id), do: nil, else: get_encounter_ids(patient_id_hash, episode_id)

    search_pipeline =
      %{"$match" => %{}}
      |> Search.add_param(%{"code" => params["code"]}, ["$match", "#{path}.code.coding"], "$elemMatch")
      |> Search.add_param(encounter_id, ["$match", "#{path}.context.identifier.value"])
      |> add_search_param(encounter_ids, ["$match", "#{path}.context.identifier.value"], "$in")
      |> Search.add_param(asserted_date_from, ["$match", "#{path}.asserted_date"], "$gte")
      |> Search.add_param(asserted_date_to, ["$match", "#{path}.asserted_date"], "$lt")

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

  def get_by_encounter_id(patient_id_hash, encounter_id) do
    @collection
    |> Mongo.aggregate([
      %{"$match" => %{"_id" => patient_id_hash}},
      %{"$project" => %{"risk_assessments" => %{"$objectToArray" => "$risk_assessments"}}},
      %{"$unwind" => "$risk_assessments"},
      %{"$match" => %{"risk_assessments.v.context.identifier.value" => encounter_id}},
      %{"$replaceRoot" => %{"newRoot" => "$risk_assessments.v"}}
    ])
    |> Enum.map(&RiskAssessment.create/1)
  end

  def fill_up_risk_assessment_performer(
        %RiskAssessment{performer: %Reference{identifier: identifier} = performer} = risk_assessment
      ) do
    with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{identifier.value}") do
      first_name = employee.party.first_name
      second_name = employee.party.second_name
      last_name = employee.party.last_name

      %{
        risk_assessment
        | performer: %{
            performer
            | display_value: "#{first_name} #{second_name} #{last_name}"
          }
      }
    else
      _ ->
        Logger.warn("Failed to fill up employee value for risk assessment")
        risk_assessment
    end
  end
end
