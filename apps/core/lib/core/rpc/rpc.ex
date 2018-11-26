defmodule Core.Rpc do
  @moduledoc false

  alias Core.Patients
  alias Core.Patients.Encounters

  def encounter_status_by_id(patient_id, id) do
    patient_id
    |> Patients.get_pk_hash()
    |> Encounters.get_status_by_id(id)
  end
end
