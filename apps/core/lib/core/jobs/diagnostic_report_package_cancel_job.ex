defmodule Core.Jobs.DiagnosticReportPackageCancelJob do
  @moduledoc """
  Struct for canceling diagnostic report package request.
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
