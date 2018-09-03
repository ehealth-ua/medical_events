defmodule Core.Jobs.EpisodeUpdateJob do
  @moduledoc """
  Struct for updating episode request.
  _id is a binded Request id. 
  """

  defstruct [
    :_id,
    :patient_id,
    :id,
    :name,
    :managing_organization,
    :care_manager,
    :user_id,
    :client_id
  ]
end
