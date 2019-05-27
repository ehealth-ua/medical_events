defmodule Core.Patients.Immunizations.VaccinationProtocol do
  @moduledoc false

  use Ecto.Schema
  alias Core.CodeableConcept
  alias Core.Validators.DictionaryReference
  import Ecto.Changeset

  @fields_required ~w()a
  @fields_optional ~w(dose_sequence description series series_doses)a

  @primary_key false
  embedded_schema do
    field(:dose_sequence, :integer)
    field(:description, :string)
    field(:series, :string)
    field(:series_doses, :integer)

    embeds_one(:authority, CodeableConcept)
    embeds_many(:target_diseases, CodeableConcept)
  end

  def changeset(%__MODULE__{} = vaccination_protocol, params) do
    vaccination_protocol
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:authority)
    |> cast_embed(:target_diseases, required: true)
    |> validate_number(:dose_sequence, greater_than: 0)
    |> validate_number(:series_doses, greater_than: 0)
    |> validate_change(:authority, &DictionaryReference.validate/2)
    |> validate_change(:target_diseases, &DictionaryReference.validate_change/2)
  end
end
