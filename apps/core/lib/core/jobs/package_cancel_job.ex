defmodule Core.Jobs.PackageCancelJob do
  @moduledoc """
  Struct for canceling package request.
  _id is a binded Request id.
  """

  defstruct [:_id, :patient_id, :signed_data, :signed_data_decoded, :entities, :user_id, :client_id]
end
