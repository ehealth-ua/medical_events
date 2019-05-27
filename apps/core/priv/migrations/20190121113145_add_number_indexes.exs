defmodule Core.Migrations.AddNumberIndexes do
  @moduledoc false

  alias Core.Mongo
  alias Core.Number

  def change do
    {:ok, _} =
      Mongo.command(
        createIndexes: Number.collection,
        indexes: [
          %{
            key: %{
              entity_type: 1,
              number: 1
            },
            name: "unique_entity_type_number_idx",
            unique: true
          }
        ]
      )
  end
end
