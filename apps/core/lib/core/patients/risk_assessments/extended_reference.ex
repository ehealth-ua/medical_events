defmodule Core.Patients.RiskAssessments.ExtendedReference do
  @moduledoc false

  use Ecto.Schema
  alias Core.Reference
  import Ecto.Changeset

  @fields_required ~w()a
  @fields_optional ~w(text)a

  @primary_key false
  embedded_schema do
    field(:text, :string)
    embeds_many(:references, Reference)
  end

  def changeset(%__MODULE__{} = extended_reference, params) do
    extended_reference
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:references)
  end

  def basis_changeset(%__MODULE__{} = extended_reference, params, options) do
    extended_reference
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:references, with: &Reference.reason_reference_changeset(&1, &2, options))
  end
end
