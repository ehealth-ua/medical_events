defmodule Core.Microservices.Casher do
  @moduledoc false

  use Core.Microservices

  @behaviour Core.Behaviours.CasherBehaviour

  @doc "params: (user_id, client_id) or employee_id"
  def get_person_data(params, headers \\ []) do
    get("/api/person_data", headers, params: params)
  end

  @doc "params: (user_id, client_id) or employee_id"
  def update_person_data(params, headers \\ []) do
    patch("/api/person_data", Jason.encode!(params), headers)
  end
end
