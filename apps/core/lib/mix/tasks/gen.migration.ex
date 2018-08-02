defmodule Mix.Tasks.Gen.Migration do
  @moduledoc false

  use Mix.Task

  import Macro, only: [camelize: 1, underscore: 1]
  import Mix.Generator

  @switches [change: :string]

  @doc false
  def run(args) do
    no_umbrella!("gen.migration")

    case OptionParser.parse(args, switches: @switches) do
      {opts, [name], _} ->
        path = Application.app_dir(:core, "priv/migrations")
        base_name = "#{underscore(name)}.exs"
        file = Path.join(path, "#{timestamp()}_#{base_name}")
        unless File.dir?(path), do: create_directory(path)

        fuzzy_path = Path.join(path, "*_#{base_name}")

        if Path.wildcard(fuzzy_path) != [] do
          Mix.raise("migration can't be created, there is already a migration file with name #{name}.")
        end

        assigns = [mod: Module.concat([Core.Migrations, camelize(name)]), change: opts[:change]]
        create_file(file, migration_template(assigns))

        file

      {_, _, _} ->
        Mix.raise(
          "expected gen.migration to receive the migration file name, " <> "got: #{inspect(Enum.join(args, " "))}"
        )
    end
  end

  def no_umbrella!(task) do
    if Mix.Project.umbrella?() do
      Mix.raise("Cannot run task #{inspect(task)} from umbrella application")
    end
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)

  embed_template(:migration, """
  defmodule <%= inspect @mod %> do
    @moduledoc false

    alias Core.Mongo

    def change do
  <%= @change %>
    end
  end
  """)
end
