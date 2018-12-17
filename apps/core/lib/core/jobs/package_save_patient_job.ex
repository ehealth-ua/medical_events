defmodule Core.Jobs.PackageSavePatientJob do
  @moduledoc """
  Struct for saving patient on create package
  _id is a binded Request id.
  """

  defstruct ~w(
    request_id
    _id
    patient_id
    patient_id_hash
    links
    patient_save_data
    encounter
    conditions
    observations
  )a
end
