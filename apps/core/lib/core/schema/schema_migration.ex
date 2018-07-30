defmodule Core.Schema.SchemaMigration do
  @moduledoc false

  require Core.Keyspaces.Events
  use Triton.Table

  table :schema_migrations, keyspace: Core.Keyspaces.Events do
    field(:version, :text)
    field(:inserted_at, :timestamp)
    partition_key([:version])
  end
end
