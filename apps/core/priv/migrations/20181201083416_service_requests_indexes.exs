defmodule Core.Migrations.ServiceRequestsIndexes do
  @moduledoc false

  alias Core.Mongo
  alias Core.ServiceRequest

  def change do
    {:ok, _} =
      Mongo.command(
        createIndexes: ServiceRequest.metadata().collection,
        indexes: [
          %{
            key: %{
              subject: 1,
              inserted_at: -1
            },
            name: "subject_inserted_at_idx"
          }
        ]
      )
  end
end
