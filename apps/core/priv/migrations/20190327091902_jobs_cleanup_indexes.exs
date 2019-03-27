defmodule Core.Migrations.JobsCleanupIndexes do
  @moduledoc false

  alias Core.Job
  alias Core.Mongo

  def change do
    {:ok, _} =
      Mongo.command(
        createIndexes: Job.metadata().collection,
        indexes: [
          %{
            key: %{
              updated_at: 1,
              status: 1
            },
            name: "autodeletion_idx"
          }
        ]
      )
  end
end
