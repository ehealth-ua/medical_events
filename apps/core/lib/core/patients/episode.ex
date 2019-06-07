defmodule Core.Episode do
  @moduledoc false

  use Ecto.Schema
  alias Core.CodeableConcept
  alias Core.Coding
  alias Core.DiagnosesHistory
  alias Core.Diagnosis
  alias Core.Ecto.UUID, as: U
  alias Core.Period
  alias Core.Reference
  alias Core.StatusHistory
  alias Core.Validators.DictionaryReference
  import Ecto.Changeset

  @fields_required ~w(id name status inserted_at updated_at inserted_by updated_by)a
  @fields_optional ~w(closing_summary explanatory_letter)a

  @status_active "active"
  @status_closed "closed"
  @status_cancelled "entered_in_error"

  def status(:active), do: @status_active
  def status(:closed), do: @status_closed
  def status(:cancelled), do: @status_cancelled

  @primary_key false
  embedded_schema do
    field(:id, U)
    field(:name, :string)
    field(:status, :string)
    field(:closing_summary, :string)
    field(:explanatory_letter, :string)
    field(:inserted_by, U)
    field(:updated_by, U)

    embeds_one(:status_reason, CodeableConcept)
    embeds_one(:period, Period, on_replace: :update)
    embeds_one(:managing_organization, Reference)
    embeds_one(:care_manager, Reference, on_replace: :update)
    embeds_many(:diagnoses_history, DiagnosesHistory)
    embeds_many(:status_history, StatusHistory)
    embeds_one(:type, Coding)
    embeds_many(:current_diagnoses, Diagnosis)

    timestamps(type: :utc_datetime_usec)
  end

  def create(data) do
    %__MODULE__{}
    |> changeset(data)
    |> apply_changes()
  end

  def changeset(%__MODULE__{} = episode, params) do
    episode
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:period)
    |> cast_embed(:managing_organization)
    |> cast_embed(:care_manager)
    |> cast_embed(:status_reason)
    |> cast_embed(:status_history)
    |> cast_embed(:type)
    |> cast_embed(:current_diagnoses)
    |> cast_embed(:diagnoses_history)
  end

  def create_changeset(%__MODULE__{} = episode, params, client_id) do
    episode
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:period, required: true)
    |> cast_embed(:managing_organization, required: true, with: &Reference.legal_entity_changeset(&1, &2, client_id))
    |> cast_embed(:care_manager,
      required: true,
      with:
        &Reference.employee_changeset(&1, &2,
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee submitted as a care_manager is not a doctor",
            status: "Doctor submitted as a care_manager is not active",
            legal_entity_id: "Employee #{get_in(&2, ~w(identifier value))} doesn't belong to your legal entity"
          ]
        )
    )
    |> cast_embed(:status_reason)
    |> cast_embed(:status_history, required: true)
    |> cast_embed(:type, required: true)
    |> cast_embed(:current_diagnoses)
    |> validate_required(@fields_required)
    |> validate_change(:status_reason, &DictionaryReference.validate_change/2)
    |> validate_change(:type, &DictionaryReference.validate_change/2)
  end

  def update_changeset(%__MODULE__{} = episode, params, client_id) do
    episode
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:managing_organization, required: true, with: &Reference.legal_entity_changeset(&1, &2, client_id))
    |> cast_embed(:care_manager,
      required: true,
      with:
        &Reference.employee_changeset(&1, &2,
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee submitted as a care_manager is not a doctor",
            status: "Doctor submitted as a care_manager is not active",
            legal_entity_id: "Employee #{get_in(&2, ~w(identifier value))} doesn't belong to your legal entity"
          ]
        )
    )
    |> validate_required(@fields_required)
  end

  def close_changeset(%__MODULE__{} = episode, params) do
    episode
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:period, required: true)
    |> validate_required(@fields_required)
  end

  def cancel_changeset(%__MODULE__{} = episode, params) do
    episode
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
  end

  def cancel_package_changeset(%__MODULE__{} = episode, params, client_id) do
    episode
    |> cast(params, [])
    |> cast_embed(:managing_organization, with: &Reference.legal_entity_changeset(&1, &2, client_id))
  end
end
