defmodule Core.Migrations.ConditionIndexes do
  @moduledoc false

  alias Core.Condition
  alias Core.Mongo

  def change do
    {:ok, _} =
      Mongo.command(
        createIndexes: Condition.collection(),
        indexes: [
          %{
            key: %{
              patient_id: 1,
              inserted_at: -1,
              code: 1
            },
            name: "patient_id_code_inserted_at_idx"
          }
        ]
      )
  end
end
