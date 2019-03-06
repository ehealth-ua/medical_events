defmodule Core.Jobs.ServiceRequestUseJob do
  @moduledoc """
  Struct for creating service request.
  _id is a binded Request id.
  """

  defstruct ~w(
    request_id
    _id
    patient_id
    patient_id_hash
    service_request_id
    used_by_employee
    used_by_legal_entity
    user_id
    client_id
  )a
end
