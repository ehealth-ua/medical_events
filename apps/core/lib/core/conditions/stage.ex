defmodule Core.Stage do
  @moduledoc false

  use Ecto.Schema
  alias Core.CodeableConcept
  alias Core.Validators.DictionaryReference
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_one(:summary, CodeableConcept)
  end

  def changeset(%__MODULE__{} = stage, params) do
    stage
    |> cast(params, [])
    |> cast_embed(:summary, required: true)
    |> validate_change(:summary, &DictionaryReference.validate_change/2)
  end
end
