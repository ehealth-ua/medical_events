defmodule Core.Patients.RiskAssessments do
  @moduledoc false

  alias Core.Mongo
  alias Core.Patient
  alias Core.Reference
  alias Core.RiskAssessment
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
