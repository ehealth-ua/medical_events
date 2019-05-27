defmodule Core.Reference do
  @moduledoc false

  use Ecto.Schema
  alias Core.Identifier
  import Ecto.Changeset
  require Logger

  @primary_key false
  embedded_schema do
    field(:display_value, :string)
    embeds_one(:identifier, Identifier, on_replace: :update)
  end

  @fields_required ~w()a
  @fields_optional ~w(display_value)a

  def create(data) do
    %__MODULE__{}
    |> changeset(data)
    |> apply_changes()
  end

  def changeset(%__MODULE__{} = reference, params) do
    reference
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:identifier)
  end

  def legal_entity_changeset(%__MODULE__{} = reference, params, client_id) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier, required: true, with: &Identifier.legal_entity_changeset(&1, &2, client_id))
  end

  def employee_changeset(%__MODULE__{} = reference, params, options \\ []) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier, required: true, with: &Identifier.employee_changeset(&1, &2, options))
  end

  def service_changeset(%__MODULE__{} = reference, params, observations) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier, required: true, with: &Identifier.service_changeset(&1, &2, observations))
  end

  def service_request_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier,
      required: true,
      with: &Identifier.service_request_changeset(&1, &2, options)
    )
  end

  def diagnostic_report_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier,
      required: true,
      with: &Identifier.diagnostic_report_changeset(&1, &2, options)
    )
  end

  def observation_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier,
      required: true,
      with: &Identifier.observation_changeset(&1, &2, options)
    )
  end

  def episode_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier,
      required: true,
      with: &Identifier.episode_changeset(&1, &2, options)
    )
  end

  def visit_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier,
      required: true,
      with: &Identifier.visit_changeset(&1, &2, options)
    )
  end

  def division_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier,
      required: true,
      with: &Identifier.division_changeset(&1, &2, options)
    )
  end

  def diagnosis_condition_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier,
      required: true,
      with: &Identifier.diagnosis_condition_changeset(&1, &2, options)
    )
  end

  def supporting_info_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier,
      required: true,
      with: &Identifier.supporting_info_changeset(&1, &2, options)
    )
  end

  def granted_resource_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier,
      required: true,
      with: &Identifier.granted_resource_changeset(&1, &2, options)
    )
  end

  def completed_with_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier,
      required: true,
      with: &Identifier.completed_with_changeset(&1, &2, options)
    )
  end

  def reason_reference_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier,
      required: true,
      with: &Identifier.reason_reference_changeset(&1, &2, options)
    )
  end

  def medication_request_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier,
      required: true,
      with: &Identifier.medication_request_changeset(&1, &2, options)
    )
  end

  def encounter_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier,
      required: true,
      with: &Identifier.encounter_changeset(&1, &2, options)
    )
  end

  def drfo_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier, required: true, with: &Identifier.drfo_changeset(&1, &2, options))
  end

  def code_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier,
      required: true,
      with: &Identifier.code_changeset(&1, &2, options)
    )
  end

  def equals_changeset(%__MODULE__{} = reference, params, options) do
    reference
    |> entity_changeset(params)
    |> cast_embed(:identifier,
      required: true,
      with: &Identifier.equals_changeset(&1, &2, options)
    )
  end

  defp entity_changeset(%__MODULE__{} = reference, params) do
    reference
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
  end
end
