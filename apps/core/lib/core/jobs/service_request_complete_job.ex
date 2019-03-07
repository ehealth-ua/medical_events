defmodule Core.Jobs.ServiceRequestCompleteJob do
  @moduledoc """
  Struct for completing service request.
  _id is a binded Request id.
  """

  defstruct ~w(
    request_id
    _id
    patient_id
    patient_id_hash
    service_request_id
    completed_with
    status_reason
    user_id
    client_id
  )a
end
