defmodule Core.Jobs.JobUpdateStatusJob do
  @moduledoc """
  Struct for updating job status.
  """

  defstruct ~w(
    request_id
    _id
    response
    status
    status_code
  )a
end
