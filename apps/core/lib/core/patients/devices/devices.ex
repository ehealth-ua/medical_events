defmodule Core.Patients.Devices do
  @moduledoc false

  alias Core.Device
  alias Core.Mongo
  alias Core.Patient
  alias Core.Source
  require Logger

  @collection Patient.metadata().collection

  def get_by_id(patient_id_hash, id) do
    with %{"devices" => %{^id => device}} <-
           Mongo.find_one(@collection, %{
             "_id" => patient_id_hash,
             "devices.#{id}" => %{"$exists" => true}
           }) do
      {:ok, Device.create(device)}
    else
      _ ->
        nil
    end
  end

  def get_by_encounter_id(patient_id_hash, %BSON.Binary{} = encounter_id) do
    @collection
    |> Mongo.aggregate([
      %{"$match" => %{"_id" => patient_id_hash}},
      %{"$project" => %{"devices" => %{"$objectToArray" => "$devices"}}},
      %{"$unwind" => "$devices"},
      %{"$match" => %{"devices.v.context.identifier.value" => encounter_id}},
      %{"$replaceRoot" => %{"newRoot" => "$devices.v"}}
    ])
    |> Enum.map(&Device.create/1)
  end

  def fill_up_device_asserter(%Device{source: %Source{type: "report_origin"}} = device), do: device

  def fill_up_device_asserter(%Device{source: %Source{value: value}} = device) do
    with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{value.identifier.value}") do
      first_name = employee.party.first_name
      second_name = employee.party.second_name
      last_name = employee.party.last_name

      %{
        device
        | source: %{
            device.source
            | value: %{
                value
                | display_value: "#{first_name} #{second_name} #{last_name}"
              }
          }
      }
    else
      _ ->
        Logger.warn("Failed to fill up employee value for device")
        device
    end
  end
end
