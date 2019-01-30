defmodule Core.Jobs.ServiceRequestCloseJob do
  @moduledoc """
  Struct for closing service request.
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
