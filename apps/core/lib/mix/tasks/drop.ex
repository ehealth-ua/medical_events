defmodule Mix.Tasks.Drop do
  @moduledoc false

  use Mix.Task

  def run(_) do
    {:ok, _} = Application.ensure_all_started(:core)
    {:ok, conn} = Mongo.start_link(url: Application.get_env(:core, :mongo)[:url])
    Mongo.command!(conn, dropDatabase: 1)
    Mix.shell().info(IO.ANSI.green() <> "Database dropped")
    Mix.shell().info("")
  end
end
