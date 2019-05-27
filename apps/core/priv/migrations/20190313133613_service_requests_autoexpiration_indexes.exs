defmodule Core.Migrations.ServiceRequestsAutoexpirationIndexes do
  @moduledoc false

  alias Core.Mongo
  alias Core.ServiceRequest

  def change do
    {:ok, _} =
      Mongo.command(
        createIndexes: ServiceRequest.collection(),
        indexes: [
          %{
            key: %{
              expiration_date: 1,
              status: 1
            },
            name: "autoexpiration_idx"
          }
        ]
      )
  end
end
