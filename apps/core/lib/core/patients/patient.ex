defmodule Core.Patient do
  @moduledoc false

  use Core.Schema

  @primary_key :_id
  schema :patients do
    field(:_id, uuid: true)
    field(:visits)
    field(:episodes)

    timestamps()
    changed_by()
  end
end
