defmodule Core.Requests.VisitCreateRequest do
  @moduledoc """
  Struct for creating visit request.
  _id is a binded Request id. 
  The rest are appropriate request fields
  """

  defstruct [:_id, :id, :visits, :signed_data]
end
