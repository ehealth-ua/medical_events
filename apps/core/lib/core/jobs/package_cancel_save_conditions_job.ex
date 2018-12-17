defmodule Core.Jobs.PackageCancelSaveConditionsJob do
  @moduledoc """
  Struct for saving conditions on cancel package
  _id is a binded Request id.
  """

  defstruct ~w(
    request_id
    _id
    patient_id
    conditions_ids
    observations_ids
    user_id
  )a
end
