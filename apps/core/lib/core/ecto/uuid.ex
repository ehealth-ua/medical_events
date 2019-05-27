defmodule Core.Ecto.UUID do
  @moduledoc false

  @behaviour Ecto.Type

  def type, do: :binary

  def cast(%BSON.Binary{} = uuid), do: {:ok, uuid}
  def cast(uuid) when is_binary(uuid), do: {:ok, uuid}

  def cast(_), do: :error
end
