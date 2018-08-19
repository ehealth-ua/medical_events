defmodule Core.Reference do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:identifier, presence: true)
  end

  def create_reference(data) do
    struct(__MODULE__, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end
