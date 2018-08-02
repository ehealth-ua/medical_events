defmodule Core.ReleaseTasks do
  @moduledoc false

  alias Core.Schema.Migrator

  def migrate do
    {:ok, _} = Application.ensure_all_started(:core)
    Mongo.start_link(name: :mongo, url: Application.get_env(:core, :mongo)[:url], pool: DBConnection.Poolboy)

    with :ok <- Migrator.migrate() do
      Mix.shell().info(IO.ANSI.green() <> "Migrations completed")
      Mix.shell().info("")
    else
      error ->
        Mix.shell().info(IO.ANSI.red() <> error)
        Mix.shell().info("")
    end
  end
end
