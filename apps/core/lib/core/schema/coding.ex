defmodule Core.Coding do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:code, :string)
    field(:system, :string)
  end

  @fields_required ~w(code system)a
  @fields_optional ~w()a

  def changeset(%__MODULE__{} = coding, params) do
    coding
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
  end
end
