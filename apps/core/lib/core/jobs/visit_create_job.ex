defmodule Core.Jobs.VisitCreateJob do
  @moduledoc """
  Struct for creating visit request.
  _id is a binded Request id. 
  """

  defstruct [:_id, :patient_id, :visit, :signed_data, :user_id, :client_id]
end
