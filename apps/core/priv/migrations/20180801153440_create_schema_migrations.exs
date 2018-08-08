defmodule Core.Migrations.CreateSchemaMigrations do
  @moduledoc false

  alias Core.Mongo
  alias Core.Schema.SchemaMigration

  def change do
    {:ok, _} =
      Mongo.command(
        createIndexes: SchemaMigration.metadata().collection,
        indexes: [
          %{
            key: %{
              version: 1
            },
            name: "unique_version_idx",
            unique: true
          }
        ]
      )
  end
end
