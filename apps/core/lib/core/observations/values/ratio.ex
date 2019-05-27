defmodule Core.Observations.Values.Ratio do
  @moduledoc false

  use Ecto.Schema
  alias Core.Observations.Values.Quantity
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_one(:numerator, Quantity)
    embeds_one(:denominator, Quantity)
  end

  def changeset(%__MODULE__{} = ratio, params) do
    ratio
    |> cast(params, [])
    |> cast_embed(:numerator, required: true)
    |> cast_embed(:denominator, required: true)
  end
end
