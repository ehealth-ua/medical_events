defmodule Core.Jobs.ServiceRequestUseJob do
  @moduledoc """
  Struct for creating service request.
  _id is a binded Request id.
  """

  defstruct [:_id, :patient_id, :patient_id_hash, :service_request_id, :used_by, :user_id, :client_id]
end
