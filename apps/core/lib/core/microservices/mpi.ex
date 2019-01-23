defmodule Core.Microservices.MPI do
  @moduledoc false

  use Core.Microservices

  @behaviour Core.Behaviours.MPIBehaviour

  def person(id, headers \\ []) do
    get!("/persons/#{id}", headers)
  end
end
