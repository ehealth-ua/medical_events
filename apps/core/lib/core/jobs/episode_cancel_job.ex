defmodule Core.Jobs.EpisodeCancelJob do
  @moduledoc """
  Struct for cancel episode request.
  _id is a binded Request id.
  """

  defstruct [
    :_id,
    :patient_id,
    :id,
    :status,
    :explanatory_letter,
    :cancellation_reason
  ]
end
