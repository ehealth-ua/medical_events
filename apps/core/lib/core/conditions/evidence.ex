defmodule Core.Evidence do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.Reference
  alias Core.Validators.DictionaryReference
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_many(:codes, CodeableConcept)
    embeds_many(:details, Reference)
  end

  def changeset(%__MODULE__{} = evidence, params) do
    evidence
    |> cast(params, [])
    |> cast_embed(:codes)
    |> cast_embed(:details)
  end

  def encounter_package_changeset(%__MODULE__{} = evidence, params, options) do
    evidence
    |> cast(params, [])
    |> cast_embed(:codes)
    |> cast_embed(:details, with: &Reference.observation_changeset(&1, &2, options))
    |> validate_change(:codes, &DictionaryReference.validate_change/2)
  end
end
