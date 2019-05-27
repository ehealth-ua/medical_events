defmodule Core.EffectiveAt do
  @moduledoc false

  use Ecto.Schema
  alias Core.Period
  import Ecto.Changeset

  @fields_required ~w()a
  @fields_optional ~w(effective_date_time)a

  @primary_key false
  embedded_schema do
    field(:effective_date_time, :utc_datetime)
    embeds_one(:effective_period, Period)
  end

  def changeset(%__MODULE__{} = effective_at, params) do
    effective_at
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:effective_period)
  end
end
