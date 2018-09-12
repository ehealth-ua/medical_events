defmodule Core.Patients.AllergyIntolerances do
  @moduledoc false

  alias Core.Mongo
  alias Core.Patient

  @collection Patient.metadata().collection

  def get(patient_id, id) do
    with %{"allergy_intolerances" => %{^id => allergy_intolerance}} <-
           Mongo.find_one(@collection, %{"_id" => patient_id}, projection: ["allergy_intolerances.#{id}": true]) do
      {:ok, allergy_intolerance}
    else
      _ ->
        nil
    end
  end
end
