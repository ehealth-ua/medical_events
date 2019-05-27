defmodule Core.Schema.Migrator do
  @moduledoc false

  alias Core.Mongo
  alias Core.Schema.SchemaMigration
  alias Ecto.Changeset

  def migrate do
    migrations_dir = Application.app_dir(:core, "priv/migrations")

    existing_migrations =
      SchemaMigration.collection()
      |> Mongo.find(%{}, projection: [_id: false, version: true])
      |> Enum.into([], fn %{"version" => version} -> version end)

    files = Path.wildcard("#{migrations_dir}/*.exs")

    Enum.each(files, fn filename ->
      migration_name =
        filename
        |> Path.basename()
        |> Path.rootname()

      if migration_name in existing_migrations do
        :ok
      else
        [{module, _}] = Code.load_file(filename)
        IO.puts("Migrating #{module}")
        apply(module, :change, [])

        schema_migration =
          %SchemaMigration{}
          |> SchemaMigration.changeset(%{
            version: migration_name,
            inserted_at: DateTime.utc_now()
          })
          |> Changeset.apply_changes()

        {:ok, _} = Mongo.insert_one(schema_migration)
      end
    end)
  end
end
