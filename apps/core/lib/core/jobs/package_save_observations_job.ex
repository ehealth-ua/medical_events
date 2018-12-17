defmodule Core.Jobs.PackageSaveObservationsJob do
  @moduledoc """
  Struct for saving observations on create package
  _id is a binded Request id.
  """

  defstruct ~w(
    request_id
    _id
    patient_id
    patient_id_hash
    id
    links
    encounter
    observations
  )a
end
