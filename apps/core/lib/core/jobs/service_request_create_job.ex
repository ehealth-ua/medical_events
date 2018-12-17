defmodule Core.Jobs.ServiceRequestCreateJob do
  @moduledoc """
  Struct for creating service request.
  _id is a binded Request id.
  """

  defstruct ~w(
    request_id
    _id
    patient_id
    patient_id_hash
    signed_data
    user_id
    client_id
  )a
end
