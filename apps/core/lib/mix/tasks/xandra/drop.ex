defmodule Mix.Tasks.Xandra.Drop do
  @moduledoc false

  use Mix.Task
  import Core.Xandra
  import Core.Keyspaces.Events, only: [get_conn: 0]

  def run(_) do
    {:ok, _} = Application.ensure_all_started(:triton)
    keyspace = Application.get_env(:triton, :clusters) |> hd |> Keyword.get(:keyspace)
    conn = get_conn()
    await_connected(conn)
    {:ok, _} = Xandra.execute(conn, "DROP KEYSPACE IF EXISTS #{keyspace}", [], pool: Xandra.Cluster)
    IO.puts([IO.ANSI.green(), "Keyspace \"#{keyspace}\" dropped"])
    IO.puts([IO.ANSI.default_color(), ""])
  end
end
