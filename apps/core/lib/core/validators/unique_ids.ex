defmodule Core.Validators.UniqueIds do
  @moduledoc false

  alias Ecto.Changeset

  def validate(field, value) do
    ids =
      Enum.map(value, fn changeset ->
        changeset
        |> Changeset.apply_changes()
        |> Map.get(:id)
      end)

    if Enum.uniq(ids) == ids do
      []
    else
      [field: "All primary keys must be unique"]
    end
  end
end
