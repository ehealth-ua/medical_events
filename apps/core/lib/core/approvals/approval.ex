defmodule Core.Approval do
  @moduledoc false

  use Ecto.Schema

  alias Core.Ecto.UUID, as: U
  alias Core.Reference
  alias Core.Validators.ApprovalGrantedToReference
  import Ecto.Changeset

  @collection "approvals"

  @status_new "new"
  @status_active "active"

  @access_level_read "read"

  def status(:new), do: @status_new
  def status(:active), do: @status_active

  def access_level(:read), do: @access_level_read

  def collection, do: @collection

  @fields_required ~w(
    _id
    patient_id
    expires_at
    urgent
    status
    access_level
    inserted_at
    updated_at
    inserted_by
    updated_by
  )a

  @fields_optional ~w()a

  @primary_key false
  schema @collection do
    field(:_id, U)
    field(:patient_id, :string)
    field(:status, :string)
    field(:access_level, :string)
    field(:expires_at, :utc_datetime)
    field(:urgent, :map)
    field(:inserted_by, U)
    field(:updated_by, U)

    embeds_one(:reason, Reference)
    embeds_one(:granted_to, Reference)
    embeds_one(:granted_by, Reference)
    embeds_many(:granted_resources, Reference)

    timestamps(type: :utc_datetime_usec)
  end

  def create(data) do
    %__MODULE__{}
    |> changeset(data)
    |> apply_changes()
  end

  def changeset(%__MODULE__{} = approval, params) do
    approval
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:granted_resources)
    |> cast_embed(:granted_to)
    |> cast_embed(:granted_by)
    |> cast_embed(:reason)
  end

  def create_changeset(%__MODULE__{} = approval, params, patient_id_hash, user_id, client_id) do
    approval
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> validate_inclusion(:status, [@status_new, @status_active])
    |> validate_inclusion(:access_level, [@access_level_read])
    |> cast_embed(:granted_resources,
      required: true,
      with: &Reference.granted_resource_changeset(&1, &2, patient_id_hash: patient_id_hash)
    )
    |> cast_embed(:granted_to,
      required: true,
      with:
        &Reference.employee_changeset(&1, &2,
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee is not an active doctor",
            status: "Employee is not an active doctor",
            legal_entity_id: "Employee #{get_in(&2, ~w(identifier value))} doesn't belong to your legal entity"
          ]
        )
    )
    |> cast_embed(:granted_by, required: true)
    |> cast_embed(:reason)
    |> validate_change(:granted_to, fn :granted_to, value ->
      granted_to = apply_changes(value)

      case ApprovalGrantedToReference.validate(granted_to.identifier.value, client_id: client_id, user_id: user_id) do
        :ok -> []
        {:error, message} -> ["granted_to.identifier.value": message]
      end
    end)
  end
end
