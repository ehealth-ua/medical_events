defmodule Core.Jobs.EpisodeCancelJob do
  @moduledoc """
  Struct for cancel episode request.
  _id is a binded Request id.
  """

  defstruct ~w(
    request_id
    _id
    patient_id
    patient_id_hash
    id
    request_params
    user_id
    client_id
  )a
end
