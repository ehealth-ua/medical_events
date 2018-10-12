defmodule Core.Jobs.PackageSaveObservationsJob do
  @moduledoc """
  Struct for saving observations on create package
  _id is a binded Request id.
  """

  defstruct [
    :_id,
    :patient_id,
    :patient_id_hash,
    :id,
    :links,
    :encounter,
    :observations
  ]
end
