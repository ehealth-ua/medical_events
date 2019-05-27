defmodule Core.Observations.Values.Quantity do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @fields_required ~w(value unit)a
  @fields_optional ~w(comparator system code)a

  @primary_key false
  embedded_schema do
    field(:value, :float)
    field(:comparator, :string)
    field(:unit, :string)
    field(:system, :string)
    field(:code, :string)
  end

  def changeset(%__MODULE__{} = quantity, params) do
    quantity
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
  end
end
