defmodule Core.Microservices.Il do
  @moduledoc """
  Il API client
  """

  use Core.Microservices

  @behaviour Core.Behaviours.IlBehaviour

  def get_dictionaries(params, headers) do
    get("/api/dictionaries", headers, params: params)
  end
end
