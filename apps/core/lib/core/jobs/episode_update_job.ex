defmodule Core.Jobs.EpisodeUpdateJob do
  @moduledoc """
  Struct for updating episode request.
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
