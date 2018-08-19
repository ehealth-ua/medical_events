defmodule Core.Identifier do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:type, presence: true)
    field(:value, presence: true)
  end

  def create_identifier(data) do
    struct(__MODULE__, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end
