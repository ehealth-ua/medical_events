defmodule Core.Patients.Immunizations.Reaction do
  @moduledoc false

  use Ecto.Schema
  alias Core.Reference
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_one(:detail, Reference)
  end

  def changeset(%__MODULE__{} = reaction, params) do
    reaction
    |> cast(params, [])
    |> cast_embed(:detail, required: true)
  end

  def encounter_package_changeset(%__MODULE__{} = reaction, params, patient_id_hash, observations) do
    reaction
    |> cast(params, [])
    |> cast_embed(:detail,
      required: true,
      with: &Reference.observation_changeset(&1, &2, patient_id_hash: patient_id_hash, observations: observations)
    )
  end
end
