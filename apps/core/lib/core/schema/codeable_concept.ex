defmodule Core.CodeableConcept do
  @moduledoc false

  use Ecto.Schema
  alias Core.Coding
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:text, :string)
    embeds_many(:coding, Coding, on_replace: :delete)
  end

  @fields_required ~w()a
  @fields_optional ~w(text)a

  def changeset(%__MODULE__{} = codeable_concept, params) do
    codeable_concept
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:coding, required: true)
  end
end
