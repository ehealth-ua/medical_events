defmodule Mix.Tasks.Migrate do
  @moduledoc false

  use Mix.Task
  alias Core.Mongo
  alias Core.Schema.Migrator

  def run(_) do
    {:ok, _} = Application.ensure_all_started(:mongodb)

    {:ok, pid} =
      Mongo.start_link(name: :mongo, url: Application.get_env(:core, :mongo)[:url], pool: DBConnection.Poolboy)

    with :ok <- Migrator.migrate() do
      Mix.shell().info(IO.ANSI.green() <> "Migrations completed" <> IO.ANSI.default_color())
      Mix.shell().info("")
    else
      error ->
        Mix.shell().info(IO.ANSI.red() <> error <> IO.ANSI.default_color())
        Mix.shell().info("")
    end

    GenServer.stop(pid)
  end
end
