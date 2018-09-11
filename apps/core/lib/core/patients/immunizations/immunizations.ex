defmodule Core.Patients.Immunizations do
  @moduledoc false

  alias Core.Mongo
  alias Core.Patient

  @collection Patient.metadata().collection

  def get(patient_id, id) do
    with %{"immunizations" => %{^id => immunization}} <-
           Mongo.find_one(@collection, %{"_id" => patient_id}, projection: ["immunizations.#{id}": true]) do
      {:ok, immunization}
    else
      _ ->
        nil
    end
  end
end
