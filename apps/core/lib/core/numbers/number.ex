defmodule Core.Number do
  @moduledoc false

  use Ecto.Schema
  alias Core.Ecto.UUID, as: U
  import Ecto.Changeset

  def collection, do: "numbers"

  @fields_required ~w(_id number entity_type inserted_by inserted_at)a
  @fields_optional ~w()a

  @primary_key false
  schema "numbers" do
    field(:_id, U)
    field(:number, :string)
    field(:entity_type, :string)
    field(:inserted_by, U)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(%__MODULE__{} = number, params) do
    number
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
  end
end
