defmodule Core.Jobs.ApprovalCreateJob do
  @moduledoc """
  Struct for creating approval request.
  _id is a binded Request id.
  """
  defstruct ~w(
    request_id
    _id
    patient_id
    patient_id_hash
    id
    resources
    service_request
    granted_to
    access_level
    user_id
    client_id
  )a
end
