defmodule Core.Migrations.ApprovalsCleanupIndexes do
  @moduledoc false

  alias Core.Approval
  alias Core.Mongo

  def change do
    {:ok, _} =
      Mongo.command(
        createIndexes: Approval.collection(),
        indexes: [
          %{
            key: %{
              inserted_at: 1,
              status: 1
            },
            name: "autodeletion_idx"
          }
        ]
      )
  end
end
