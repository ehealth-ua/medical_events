defmodule Core.Jobs.PackageSaveConditionsJob do
  @moduledoc """
  Struct for saving conditions on create package
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
    conditions
    observations
  )a
end
