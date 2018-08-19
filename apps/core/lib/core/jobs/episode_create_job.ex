defmodule Core.Jobs.EpisodeCreateJob do
  @moduledoc """
  Struct for creating episode request.
  _id is a binded Request id. 
  """

  defstruct [
    :_id,
    :patient_id,
    :id,
    :name,
    :type,
    :status,
    :managing_organization,
    :period,
    :care_manager,
    :user_id
  ]
end
