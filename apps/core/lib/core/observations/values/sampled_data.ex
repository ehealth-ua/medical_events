defmodule Core.Observations.Values.SampledData do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @fields_required ~w(data)a
  @fields_optional ~w(origin period factor lower_limit upper_limit dimensions)a

  @primary_key false
  embedded_schema do
    field(:origin, :float)
    field(:period, :float)
    field(:factor, :float)
    field(:lower_limit, :float)
    field(:upper_limit, :float)
    field(:dimensions, :float)
    field(:data, :string)
  end

  def changeset(%__MODULE__{} = sampled_data, params) do
    sampled_data
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
  end
end
