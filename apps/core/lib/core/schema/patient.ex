defmodule Core.Schema.Patient do
  @moduledoc false

  require Core.Keyspaces.Events
  alias Core.Schema.Timestamp
  use Triton.Table

  table :patients, keyspace: Core.Keyspaces.Events do
    # validators using vex
    field(:person_id, :text)
    # field(:user_id, :bigint, validators: [presence: true])
    # field(:username, :text)
    # field(:display_name, :text)
    # field(:password, :text)
    # field(:email, :text)
    # field(:phone, :text)
    # field(:notifications, {:map, "<text, text>"})
    # field(:friends, {:set, "<text>"})
    # field(:posts, {:list, "<text>"})
    field(:updated_at, :timestamp)
    field(:inserted_at, :timestamp)
    field(:updated_by, :text, validators: [uuid: true])
    field(:inserted_by, :text, validators: [uuid: true])
    field(:visits, {:list, "<FROZEN<visit>>"})
    # field(:visits, {:map, "<text, FROZEN<period>>"})
    # embeds_many(:visits, Visit)

    partition_key([:person_id])
  end
end
