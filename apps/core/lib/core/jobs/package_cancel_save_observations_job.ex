defmodule Core.Jobs.PackageCancelSaveObservationsJob do
  @moduledoc """
  Struct for saving observations on cancel package
  _id is a binded Request id.
  """

  defstruct ~w(
    request_id
    _id
    patient_id
    observations_ids
    user_id
  )a
end
