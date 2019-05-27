defmodule Core.StatusHistory do
  @moduledoc false

  use Ecto.Schema
  alias Core.CodeableConcept
  alias Core.Ecto.UUID, as: U
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:status, :string)
    field(:inserted_by, U)

    embeds_one(:status_reason, CodeableConcept)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @fields_required ~w(status inserted_by inserted_at)a
  @fields_optional ~w()a

  def create(data) do
    %__MODULE__{}
    |> changeset(data)
    |> apply_changes()
  end

  def changeset(%__MODULE__{} = reference, params) do
    reference
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:status_reason)
  end
end
