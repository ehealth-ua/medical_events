defmodule Core.ReleaseTasks do
  @moduledoc false

  alias Core.Schema.Migrator
  require Logger

  def migrate do
    {:ok, _} = Application.ensure_all_started(:core)
    Mongo.start_link(name: :mongo, url: Application.get_env(:core, :mongo)[:url], pool: DBConnection.Poolboy)
    {:ok, _} = Cluster.Supervisor.start_link([Application.get_env(:api, :topologies), [name: API.ClusterSupervisor]])

    with :ok <- Migrator.migrate() do
      Logger.info(IO.ANSI.green() <> "Migrations completed")
    else
      error ->
        Logger.info(IO.ANSI.red() <> error)
    end
  end
end
