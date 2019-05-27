defmodule Core.Patients.Immunizations.Explanation do
  @moduledoc false

  use Ecto.Schema
  alias Core.CodeableConcept
  alias Core.Validators.DictionaryReference
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_many(:reasons, CodeableConcept)
    embeds_many(:reasons_not_given, CodeableConcept)
  end

  def changeset(%__MODULE__{} = explanation, params) do
    explanation
    |> cast(params, [])
    |> cast_embed(:reasons)
    |> cast_embed(:reasons_not_given)
    |> validate_change(:reasons, &DictionaryReference.validate_change/2)
    |> validate_change(:reasons_not_given, &DictionaryReference.validate_change/2)
  end
end
