defmodule Core.Jobs.ServiceRequestReleaseJob do
  @moduledoc """
  Struct for releasing service request.
  _id is a binded Request id.
  """

  defstruct ~w(
    request_id
    _id
    patient_id
    patient_id_hash
    service_request_id
    user_id
    client_id
  )a
end
