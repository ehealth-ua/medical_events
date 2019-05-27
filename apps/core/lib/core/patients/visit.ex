defmodule Core.Visit do
  @moduledoc false

  use Ecto.Schema
  alias Core.Ecto.UUID, as: U
  alias Core.Period
  import Ecto.Changeset

  @fields_required ~w(id inserted_at updated_at inserted_by updated_by)a
  @fields_optional ~w()a

  @primary_key false
  embedded_schema do
    field(:id, U)
    field(:inserted_by, U)
    field(:updated_by, U)

    embeds_one(:period, Period, on_replace: :update)

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(%__MODULE__{} = episode, params) do
    episode
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:period, required: true)
    |> validate_required(@fields_required)
  end
end
