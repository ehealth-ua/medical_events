defmodule Core.Migrations.CreateTypes do
  @moduledoc false

  def change(conn) do
    {:ok, _} =
      Xandra.execute(
        conn,
        "CREATE TYPE IF NOT EXISTS period (start timestamp, end timestamp)",
        [],
        pool: Xandra.Cluster
      )

    {:ok, _} =
      Xandra.execute(
        conn,
        "CREATE TYPE IF NOT EXISTS visit (id text, inserted_at timestamp, updated_at timestamp, inserted_by text, updated_by text, period frozen<period>)",
        [],
        pool: Xandra.Cluster
      )
  end
end
