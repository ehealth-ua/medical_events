defmodule NumberGenerator.Rpc do
  @moduledoc """
  This module contains functions that are called from other pods via RPC.
  """

  alias NumberGenerator.Generator

  @doc """
   Generate new requisition number

  ## Examples

      iex> NumberGenerator.Rpc.number(
        "episode",
        "26e673e1-1d68-413e-b96c-407b45d9f572",
        "7a1419b0-c53d-4df2-9c22-07de28d96ac0"
      )
      {:ok, "8830-3875-8474-6820"}
  """
  @spec number(entity_type :: binary(), id :: binary(), actor_id :: binary()) :: {:ok, binary()}
  def number(entity_type, id, actor_id) do
    {:ok, Generator.generate(entity_type, id, actor_id)}
  end
end
