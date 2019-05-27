defmodule Core.Schema.SchemaMigration do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @fields_required ~w(version inserted_at)a
  @fields_optional ~w()a

  def collection, do: "schema_migrations"

  @primary_key false
  schema "schema_migrations" do
    field(:version, :string)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(%__MODULE__{} = schema_migration, params) do
    schema_migration
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
  end
end
