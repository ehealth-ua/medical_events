defmodule Core.Jobs.PackageCancelSavePatientJob do
  @moduledoc """
  Struct for saving patient on cancel package
  _id is a binded Request id.
  """

  defstruct [
    :_id,
    :patient_id,
    :patient_id_hash,
    :patient_save_data,
    :conditions_ids,
    :observations_ids,
    :user_id
  ]
end
