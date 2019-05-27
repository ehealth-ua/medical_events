defmodule Core.Ecto.IdentifierValue do
  @moduledoc false

  @behaviour Ecto.Type

  def type, do: :string

  def cast(%BSON.Binary{} = uuid), do: {:ok, to_string(uuid)}
  def cast(value) when is_binary(value), do: {:ok, value}

  def cast(_), do: :error
end
