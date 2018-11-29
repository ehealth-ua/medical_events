defmodule Core.Jobs.JobUpdateStatusJob do
  @moduledoc """
  Struct for updating job status.
  """

  defstruct [:_id, :response, :status, :status_code]
end
