defmodule Mix.Tasks.Drop do
  @moduledoc false

  use Mix.Task
  alias Core.Mongo

  def run(_) do
    {:ok, _} = Application.ensure_all_started(:mongodb)

    {:ok, pid} =
      Mongo.start_link(name: :mongo, url: Application.get_env(:core, :mongo)[:url], pool: DBConnection.Poolboy)

    Mongo.command!(dropDatabase: 1)
    Mix.shell().info(IO.ANSI.green() <> "Database dropped" <> IO.ANSI.default_color())
    Mix.shell().info("")

    GenServer.stop(pid)
  end
end
