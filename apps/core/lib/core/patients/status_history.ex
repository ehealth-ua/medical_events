defmodule Core.StatusHistory do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:status, presence: true)
    field(:inserted_at, presence: true)
    field(:inserted_by, presence: true, uuid: true)
  end

  def create(data) do
    struct(__MODULE__, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end
