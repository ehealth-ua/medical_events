defmodule Core.Number do
  @moduledoc false

  use Core.Schema

  @primary_key :_id
  schema :numbers do
    field(:_id, presence: true, mongo_uuid: true)
    field(:number, presence: true)
    field(:entity_type, presence: true)
    field(:inserted_by, presence: true, mongo_uuid: true)
  end
end
