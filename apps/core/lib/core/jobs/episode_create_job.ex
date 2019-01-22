defmodule Core.Jobs.EpisodeCreateJob do
  @moduledoc """
  Struct for creating episode request.
  _id is a binded Request id.
  """

  defstruct ~w(
    request_id
    _id
    patient_id
    patient_id_hash
    id
    name
    type
    status
    managing_organization
    period
    care_manager
    referral_requests
    user_id
    client_id
  )a
end
