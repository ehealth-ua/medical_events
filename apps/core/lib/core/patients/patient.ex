defmodule Core.Patient do
  @moduledoc false

  use Core.Schema

  @primary_key :id
  schema :patients do
    field(:id, uuid: true)
    field(:visits)
    field(:episodes)

    timestamps()
    changed_by()
  end
end
