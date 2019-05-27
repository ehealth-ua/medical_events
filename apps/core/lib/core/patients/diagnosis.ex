defmodule Core.Diagnosis do
  @moduledoc false

  use Ecto.Schema
  alias Core.CodeableConcept
  alias Core.Reference
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:rank, :integer)

    embeds_one(:condition, Reference)
    embeds_one(:role, CodeableConcept)
    embeds_one(:code, CodeableConcept)
  end

  @fields_required ~w()a
  @fields_optional ~w(rank)a

  def create(data) do
    %__MODULE__{}
    |> changeset(data)
    |> apply_changes()
  end

  def changeset(%__MODULE__{} = reference, params) do
    reference
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:condition)
    |> cast_embed(:role)
    |> cast_embed(:code)
  end

  def encounter_changeset(%__MODULE__{} = reference, params, patient_id_hash, conditions) do
    reference
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:condition,
      required: true,
      with: &Reference.diagnosis_condition_changeset(&1, &2, conditions: conditions, patient_id_hash: patient_id_hash)
    )
    |> cast_embed(:role, required: true)
    |> cast_embed(:code)
  end
end
