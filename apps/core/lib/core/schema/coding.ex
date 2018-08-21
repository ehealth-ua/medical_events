defmodule Core.Coding do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:system, presence: true)
    field(:code, presence: true)
    field(:display)
  end

  def create_coding(data) do
    struct(__MODULE__, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end