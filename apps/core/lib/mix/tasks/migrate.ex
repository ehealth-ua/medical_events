defmodule Mix.Tasks.Migrate do
  @moduledoc false

  use Mix.Task
  alias Core.Mongo
  alias Core.Schema.Migrator
  require Logger

  def run(_) do
    {:ok, _} = Application.ensure_all_started(:mongodb)

    {:ok, pid} =
      Mongo.start_link(name: :mongo, url: Application.get_env(:core, :mongo)[:url], pool: DBConnection.Poolboy)

    with :ok <- Migrator.migrate() do
      Logger.info(IO.ANSI.green() <> "Migrations completed" <> IO.ANSI.default_color())
    else
      error ->
        Logger.info(IO.ANSI.red() <> error <> IO.ANSI.default_color())
    end

    GenServer.stop(pid)
  end
end
