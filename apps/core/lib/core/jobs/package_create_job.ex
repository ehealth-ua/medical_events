defmodule Core.Jobs.PackageCreateJob do
  @moduledoc """
  Struct for creating package request.
  _id is a binded Request id.
  """

  defstruct ~w(
    request_id
    _id
    patient_id
    patient_id_hash
    visit
    signed_data
    user_id
    client_id
  )a
end
