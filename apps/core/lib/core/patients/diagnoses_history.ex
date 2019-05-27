defmodule Core.DiagnosesHistory do
  @moduledoc false

  use Ecto.Schema
  alias Core.Diagnosis
  alias Core.Reference
  import Ecto.Changeset

  @fields_required ~w(date is_active)a
  @fields_optional ~w()a

  @primary_key false
  embedded_schema do
    field(:date, :utc_datetime_usec)
    field(:is_active, :boolean)

    embeds_one(:evidence, Reference)
    embeds_many(:diagnoses, Diagnosis)
  end

  def changeset(%__MODULE__{} = reference, params) do
    reference
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:evidence)
    |> cast_embed(:diagnoses)
  end

  def create_changeset(%__MODULE__{} = reference, params) do
    reference
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:evidence, required: true)
    |> cast_embed(:diagnoses, required: true)
  end
end
