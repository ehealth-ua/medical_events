defmodule Core.Schema.Migrator do
  @moduledoc false

  alias Core.Mongo
  alias Core.Schema.SchemaMigration

  def migrate do
    migrations_dir = Application.app_dir(:core, "priv/migrations")

    existing_migrations =
      SchemaMigration.metadata().collection
      |> to_string()
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

        {:ok, _} =
          Mongo.insert_one(%SchemaMigration{
            version: migration_name,
            inserted_at: DateTime.utc_now()
          })
      end
    end)
  end
end
