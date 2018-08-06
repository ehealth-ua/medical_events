defmodule Core.Visit do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:id, presence: true)
    field(:period)

    timestamps()
    changed_by()
  end
end
