defmodule Core.Migrations.ObservationIndexes do
  @moduledoc false

  alias Core.Mongo
  alias Core.Observation

  def change do
    {:ok, _} =
      Mongo.command(
        createIndexes: Observation.metadata().collection,
        indexes: [
          %{
            key: %{
              patient_id: 1,
              inserted_at: -1,
              code: 1,
            },
            name: "patient_id_code_inserted_at_idx",
          }
        ]
      )
  end
end
