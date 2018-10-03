defmodule Core.Patients.Immunizations do
  @moduledoc false

  alias Core.Immunization
  alias Core.Mongo
  alias Core.Patient
  alias Core.Source
  require Logger

  @collection Patient.metadata().collection

  def get(patient_id_hash, id) do
    with %{"immunizations" => %{^id => immunization}} <-
           Mongo.find_one(@collection, %{"_id" => patient_id_hash}, projection: ["immunizations.#{id}": true]) do
      {:ok, immunization}
    else
      _ ->
        nil
    end
  end

  def fill_up_immunization_performer(%Immunization{source: %Source{type: "report_origin"}} = immunization) do
    immunization
  end

  def fill_up_immunization_performer(%Immunization{source: %Source{value: value}} = immunization) do
    with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{value.identifier.value}") do
      first_name = get_in(employee, ["party", "first_name"])
      second_name = get_in(employee, ["party", "second_name"])
      last_name = get_in(employee, ["party", "last_name"])

      %{
        immunization
        | source: %{
            immunization.source
            | value: %{
                value
                | display_value: "#{first_name} #{second_name} #{last_name}"
              }
          }
      }
    else
      _ ->
        Logger.warn("Failed to fill up employee value for immunization")
        immunization
    end
  end

  def get_by_encounter_id(patient_id_hash, encounter_id) do
    @collection
    |> Mongo.aggregate([
      %{"$match" => %{"_id" => patient_id_hash}},
      %{"$project" => %{"immunizations" => %{"$objectToArray" => "$immunizations"}}},
      %{"$unwind" => "$immunizations"},
      %{"$match" => %{"immunizations.v.context.identifier.value" => encounter_id}},
      %{"$replaceRoot" => %{"newRoot" => "$immunizations.v"}}
    ])
    |> Enum.map(&Immunization.create/1)
  end
end
