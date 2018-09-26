defmodule Core.Patients.Immunizations do
  @moduledoc false

  alias Core.Immunization
  alias Core.Mongo
  alias Core.Patient
  alias Core.Patients
  alias Core.Source
  require Logger

  @collection Patient.metadata().collection

  def get(patient_id, id) do
    with %{"immunizations" => %{^id => immunization}} <-
           Mongo.find_one(@collection, %{"_id" => Patients.get_pk_hash(patient_id)},
             projection: ["immunizations.#{id}": true]
           ) do
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
end
