defmodule Core.ServiceRequest do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.Ecto.UUID, as: U
  alias Core.Encryptor
  alias Core.Episode
  alias Core.Patients.Encounters
  alias Core.Reference
  alias Core.ServiceRequests.Occurrence
  alias Core.StatusHistory
  alias Core.Validators.DateTime, as: DateTimeValidator
  alias Core.Validators.DictionaryReference
  alias Ecto.Changeset
  import Ecto.Changeset

  def collection, do: "service_requests"

  @worker Application.get_env(:core, :rpc_worker)

  @status_active "active"
  @status_in_progress "in_progress"
  @status_completed "completed"
  @status_entered_in_error "entered_in_error"
  @status_recalled "recalled"

  @intent_order "order"
  @intent_plan "plan"

  @laboratory_procedure "laboratory_procedure"
  @counselling "counselling"

  def status(:active), do: @status_active
  def status(:in_progress), do: @status_in_progress
  def status(:completed), do: @status_completed
  def status(:entered_in_error), do: @status_entered_in_error
  def status(:recalled), do: @status_recalled

  def intent(:order), do: @intent_order
  def intent(:plan), do: @intent_plan

  def category(:laboratory_procedure), do: @laboratory_procedure
  def category(:counselling), do: @counselling

  @fields_required ~w(_id status intent subject authored_on inserted_at updated_at inserted_by updated_by)a

  @fields_optional ~w(
    explanatory_letter
    priority
    note
    patient_instruction
    signed_content_links
    expiration_date
    requisition
  )a

  @primary_key false
  schema "service_requests" do
    field(:_id, U)
    field(:status, :string)
    field(:explanatory_letter, :string)
    field(:intent, :string)
    field(:subject, :string)
    field(:authored_on, :utc_datetime_usec)
    field(:priority, :string)
    field(:note, :string)
    field(:patient_instruction, :string)
    field(:expiration_date, :utc_datetime)
    field(:signed_content_links, {:array, :string})
    field(:requisition, :string)
    field(:inserted_by, U)
    field(:updated_by, U)

    embeds_one(:status_reason, CodeableConcept)
    embeds_many(:status_history, StatusHistory)
    embeds_one(:category, CodeableConcept)
    embeds_one(:code, Reference)
    embeds_one(:context, Reference)
    embeds_one(:occurrence, Occurrence)
    embeds_one(:requester_employee, Reference)
    embeds_one(:requester_legal_entity, Reference)
    embeds_many(:reason_reference, Reference)
    embeds_many(:supporting_info, Reference)
    embeds_many(:permitted_resources, Reference)
    embeds_one(:used_by_employee, Reference, on_replace: :delete)
    embeds_one(:used_by_legal_entity, Reference, on_replace: :delete)
    embeds_one(:completed_with, Reference)

    timestamps(type: :utc_datetime_usec)
  end

  def create(data) do
    %__MODULE__{}
    |> changeset(data)
    |> apply_changes()
  end

  def changeset(%__MODULE__{} = service_request, params) do
    service_request
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:status_reason)
    |> cast_embed(:status_history)
    |> cast_embed(:category)
    |> cast_embed(:code)
    |> cast_embed(:context)
    |> cast_embed(:occurrence)
    |> cast_embed(:requester_employee)
    |> cast_embed(:requester_legal_entity)
    |> cast_embed(:reason_reference)
    |> cast_embed(:supporting_info)
    |> cast_embed(:permitted_resources)
    |> cast_embed(:used_by_employee)
    |> cast_embed(:used_by_legal_entity)
    |> cast_embed(:completed_with)
  end

  def create_changeset(%__MODULE__{} = service_request, params, patient_id_hash, user_id, client_id) do
    changeset =
      service_request
      |> cast(params, @fields_required ++ @fields_optional)
      |> validate_required(@fields_required)
      |> cast_embed(:status_reason)
      |> cast_embed(:status_history)
      |> cast_embed(:category)
      |> cast_embed(:context, with: &Reference.encounter_changeset(&1, &2, patient_id_hash: patient_id_hash))
      |> put_requisition_number(patient_id_hash, user_id)
      |> cast_embed(:occurrence)
      |> cast_embed(:requester_employee, required: true)
      |> cast_embed(:requester_legal_entity,
        required: true,
        with:
          &Reference.equals_changeset(&1, &2,
            value: client_id,
            message: "Must be current legal enity"
          )
      )
      |> cast_embed(:reason_reference,
        with: &Reference.reason_reference_changeset(&1, &2, patient_id_hash: patient_id_hash)
      )
      |> cast_embed(:supporting_info,
        with:
          &Reference.supporting_info_changeset(&1, &2,
            patient_id_hash: patient_id_hash,
            status: Episode.status(:active)
          )
      )

    category_value = changeset |> get_change(:category) |> get_change(:coding) |> hd() |> get_change(:code)

    changeset
    |> validate_permitted_resources(category_value, patient_id_hash)
    |> cast_embed(:code, with: &Reference.code_changeset(&1, &2, category: category_value))
    |> cast_embed(:used_by_employee)
    |> cast_embed(:used_by_legal_entity)
    |> cast_embed(:completed_with)
    |> validate_change(:category, &DictionaryReference.validate_change/2)
    |> validate_change(
      :authored_on,
      &DateTimeValidator.validate_change(&1, &2, less_than: DateTime.utc_now())
    )
  end

  def use_changeset(%__MODULE__{} = service_request, params, client_id) do
    service_request
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:used_by_employee,
      with:
        &Reference.employee_changeset(&1, &2,
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee is not an active doctor",
            status: "Employee is not approved",
            legal_entity_id: "Employee #{get_in(&2, ~w(identifier value))} doesn't belong to your legal entity"
          ]
        )
    )
    |> cast_embed(:used_by_legal_entity,
      required: true,
      with:
        &Reference.equals_changeset(&1, &2,
          value: client_id,
          message: "You can assign service request only to your legal entity"
        )
    )
  end

  def release_changeset(%__MODULE__{} = service_request, params) do
    service_request
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:used_by_employee)
    |> cast_embed(:used_by_legal_entity)
  end

  def recall_changeset(%__MODULE__{} = service_request, params) do
    service_request
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:status_reason)
  end

  def cancel_changeset(%__MODULE__{} = service_request, params) do
    service_request
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:status_reason)
  end

  def close_changeset(%__MODULE__{} = service_request, params) do
    service_request
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
  end

  def complete_changeset(%__MODULE__{} = service_request, params, patient_id_hash) do
    service_request
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:completed_with, with: &Reference.completed_with_changeset(&1, &2, patient_id_hash: patient_id_hash))
    |> cast_embed(:status_reason)
  end

  def process_changeset(%__MODULE__{} = service_request, params) do
    service_request
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
  end

  defp validate_permitted_resources(changeset, category_value, patient_id_hash) do
    permitted_resources =
      changeset
      |> cast_embed(:permitted_resources)
      |> get_change(:permitted_resources)

    if category_value == category(:laboratory_procedure) and !is_nil(permitted_resources) do
      add_error(
        changeset,
        :permitted_resources,
        "Permitted resources are not allowed for laboratory category of service request"
      )
    else
      cast_embed(
        changeset,
        :permitted_resources,
        with:
          &Reference.supporting_info_changeset(&1, &2,
            patient_id_hash: patient_id_hash,
            status: Episode.status(:active)
          )
      )
    end
  end

  defp put_requisition_number(%Changeset{valid?: true} = changeset, patient_id_hash, user_id) do
    encounter_id = changeset |> get_change(:context) |> get_change(:identifier) |> get_change(:value)

    with {_, {:ok, encounter}} <-
           {:encounter, Encounters.get_by_id(patient_id_hash, to_string(encounter_id))},
         {:ok, number} <-
           @worker.run("number_generator", NumberGenerator.Rpc, :number, [
             "encounter",
             to_string(encounter.identifier.value),
             user_id
           ]) do
      put_change(changeset, :requisition, number)
    else
      _ -> add_error(changeset, :requisition, "Failed to generate requisition number")
    end
  end

  defp put_requisition_number(changeset, _, _), do: changeset
end
