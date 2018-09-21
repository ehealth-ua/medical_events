defmodule Core.Patients.AllergyIntolerances do
  @moduledoc false

  alias Core.AllergyIntolerance
  alias Core.Mongo
  alias Core.Patient
  alias Core.Patients
  alias Core.Source
  require Logger

  @collection Patient.metadata().collection

  def get(patient_id, id) do
    with %{"allergy_intolerances" => %{^id => allergy_intolerance}} <-
           Mongo.find_one(@collection, %{"_id" => Patients.get_pk_hash(patient_id)},
             projection: ["allergy_intolerances.#{id}": true]
           ) do
      {:ok, allergy_intolerance}
    else
      _ ->
        nil
    end
  end

  def fill_up_allergy_intolerance_asserter(
        %AllergyIntolerance{source: %Source{type: "report_origin"}} = allergy_intolerance
      ) do
    allergy_intolerance
  end

  def fill_up_allergy_intolerance_asserter(%AllergyIntolerance{source: %Source{value: value}} = allergy_intolerance) do
    with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{value.identifier.value}") do
      first_name = get_in(employee, ["party", "first_name"])
      second_name = get_in(employee, ["party", "second_name"])
      last_name = get_in(employee, ["party", "last_name"])

      %{
        allergy_intolerance
        | source: %{
            allergy_intolerance.source
            | value: %{
                value
                | display_value: "#{first_name} #{second_name} #{last_name}"
              }
          }
      }
    else
      _ ->
        Logger.warn("Failed to fill up employee value for allergy_intolerance")
        allergy_intolerance
    end
  end

  def get_by_encounter_id(patient_id, encounter_id) do
    @collection
    |> Mongo.aggregate([
      %{"$match" => %{"_id" => patient_id}},
      %{"$project" => %{"allergy_intolerances" => %{"$objectToArray" => "$allergy_intolerances"}}},
      %{"$unwind" => "$allergy_intolerances"},
      %{"$match" => %{"allergy_intolerances.v.context.identifier.value" => encounter_id}},
      %{"$replaceRoot" => %{"newRoot" => "$allergy_intolerances.v"}}
    ])
    |> Enum.to_list()
  end
end
