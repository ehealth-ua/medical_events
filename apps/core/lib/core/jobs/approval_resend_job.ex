defmodule Core.Jobs.ApprovalResendJob do
  @moduledoc """
  Struct for resending approval request.
  _id is a binded Request id.
  """
  defstruct ~w(
    request_id
    _id
    patient_id
    patient_id_hash
    id
    user_id
    client_id
  )a
end
