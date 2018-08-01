defmodule Core.Patient do
  @moduledoc false

  use Core.Schema

  @primary_key :_id
  schema :patients do
    field(:_id, uuid: true)
    field(:visits)
    field(:episodes)
    field(:immunizations)
    field(:allergy_intolerances)

    timestamps()
    changed_by()
  end
end
