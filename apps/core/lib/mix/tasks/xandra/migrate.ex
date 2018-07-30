defmodule Mix.Tasks.Xandra.Migrate do
  @moduledoc false

  use Mix.Task
  alias Core.Schema.SchemaMigration

  import Triton.Query
  import Core.Xandra
  import Core.Keyspaces.Events, only: [get_conn: 0]

  def run(_) do
    {:ok, _} = Application.ensure_all_started(:triton)
    conn = get_conn()
    await_connected(conn)

    statement =
      create_table(%{
        __name__: "schema_migrations",
        __fields__: [{:version, %{type: :text}}, {:inserted_at, %{type: :timestamp}}],
        __partition_key__: [:version],
        __cluster_columns__: nil,
        __with_options__: nil
      })

    Xandra.execute!(conn, statement, [], pool: Xandra.Cluster)

    {:ok, existing_migrations} =
      SchemaMigration
      |> select([:version])
      |> SchemaMigration.all()

    path = Path.join(Mix.Project.deps_paths()[:core] || File.cwd!(), "priv/migrations")
    files = Path.wildcard("#{path}/*.exs")

    Enum.map(files, fn filename ->
      migration_name =
        filename
        |> Path.basename()
        |> Path.rootname()

      if migration_name in existing_migrations do
        :ok
      else
        [{module, _}] = Code.load_file(filename)
        apply(module, :change, [conn])

        {:ok, :success} =
          SchemaMigration
          |> insert(version: migration_name, inserted_at: :os.system_time(:millisecond))
          |> SchemaMigration.save()
      end
    end)

    IO.puts([IO.ANSI.green(), "All migrations are completed"])
    IO.puts([IO.ANSI.default_color(), ""])
  end
end
