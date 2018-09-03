defmodule Core.Microservices.Il do
  @moduledoc """
  Il API client
  """

  use Core.Microservices

  @behaviour Core.Behaviours.IlBehaviour

  def get_dictionaries(params, headers) do
    get("/api/dictionaries", headers, params: params)
  end

  def get_legal_entity(id, headers) do
    get("/api/legal_entities/#{id}", headers)
  end

  def get_employee(id, headers) do
    get("/api/employees/#{id}", headers)
  end

  def get_division(id, headers) do
    get("/api/divisions/#{id}", headers)
  end
end
