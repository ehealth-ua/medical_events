defmodule Core.Behaviours.MPIBehaviour do
  @moduledoc false

  @callback person(id :: binary, headers :: list) :: {:ok, result :: term} | {:error, reason :: term}
end
