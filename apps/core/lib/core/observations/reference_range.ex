defmodule Core.Observations.ReferenceRange do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.Observations.Values.Quantity
  alias Core.Range
  import Ecto.Changeset

  @fields_required ~w()a
  @fields_optional ~w(text)a

  @primary_key false
  embedded_schema do
    field(:text, :string)

    embeds_one(:type, CodeableConcept)
    embeds_many(:applies_to, CodeableConcept)
    embeds_one(:low, Quantity)
    embeds_one(:high, Quantity)
    embeds_one(:age, Range)
  end

  def changeset(%__MODULE__{} = reference_range, params) do
    reference_range
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:type)
    |> cast_embed(:applies_to)
    |> cast_embed(:low)
    |> cast_embed(:high)
    |> cast_embed(:age)
  end
end
