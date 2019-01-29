defmodule Core.Jobs.ServiceRequestCancelJob do
  @moduledoc """
  Struct for cancelling service request.
  _id is a binded Request id.
  """

  defstruct ~w(
    request_id
    _id
    patient_id
    patient_id_hash
    service_request_id
    signed_data
    user_id
    client_id
  )a
end
