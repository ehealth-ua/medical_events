defmodule Core.Range do
  @moduledoc false

  use Ecto.Schema
  alias Core.Observations.Values.Quantity
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_one(:low, Quantity)
    embeds_one(:high, Quantity)
  end

  def changeset(%__MODULE__{} = range, params) do
    range
    |> cast(params, [])
    |> cast_embed(:low, required: true)
    |> cast_embed(:high, required: true)
  end
end
