defmodule Core.RiskAssessment do
  @moduledoc false

  use Ecto.Schema

  alias Core.CacheHelper
  alias Core.CodeableConcept
  alias Core.Ecto.UUID, as: U
  alias Core.Patients.RiskAssessments.ExtendedReference
  alias Core.Patients.RiskAssessments.Prediction
  alias Core.Patients.RiskAssessments.Reason
  alias Core.Reference
  alias Core.Validators.DictionaryReference
  import Ecto.Changeset
  require Logger

  @status_preliminary "preliminary"
  @status_final "final"
  @status_entered_in_error "entered_in_error"

  def status(:preliminary), do: @status_preliminary
  def status(:final), do: @status_final
  def status(:entered_in_error), do: @status_entered_in_error

  @fields_required ~w(
    id
    status
    asserted_date
    inserted_at
    updated_at
    inserted_by
    updated_by
  )a
  @fields_optional ~w(mitigation comment)a

  @primary_key false
  embedded_schema do
    field(:id, U)
    field(:status, :string)
    field(:asserted_date, :utc_datetime)
    field(:mitigation, :string)
    field(:comment, :string)
    field(:inserted_by, U)
    field(:updated_by, U)

    embeds_one(:method, CodeableConcept)
    embeds_one(:code, CodeableConcept)
    embeds_one(:context, Reference)
    embeds_one(:performer, Reference)
    embeds_one(:reason, Reason)
    embeds_one(:basis, ExtendedReference)
    embeds_many(:predictions, Prediction)

    timestamps(type: :utc_datetime_usec)
  end

  def create(data) do
    %__MODULE__{}
    |> changeset(data)
    |> apply_changes()
  end

  def changeset(%__MODULE__{} = risk_assessment, params) do
    risk_assessment
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:method)
    |> cast_embed(:code)
    |> cast_embed(:context)
    |> cast_embed(:performer)
    |> cast_embed(:reason)
    |> cast_embed(:basis)
  end

  def encounter_package_changeset(
        %__MODULE__{} = risk_assessment,
        params,
        patient_id_hash,
        observations,
        conditions,
        diagnostic_reports,
        encounter_id,
        client_id
      ) do
    risk_assessment
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:method)
    |> cast_embed(:code, required: true)
    |> cast_embed(:context,
      required: true,
      with:
        &Reference.equals_changeset(&1, &2,
          value: encounter_id,
          message: "Submitted context is not allowed for the risk assessment"
        )
    )
    |> cast_embed(:performer,
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
    |> cast_embed(:reason,
      with:
        &Reason.encounter_package_changeset(
          &1,
          &2,
          patient_id_hash,
          observations,
          conditions,
          diagnostic_reports
        )
    )
    |> cast_embed(:basis,
      with:
        &ExtendedReference.basis_changeset(&1, &2,
          patient_id_hash: patient_id_hash,
          observarvations: observations,
          conditions: conditions,
          diagnostic_reports: diagnostic_reports
        )
    )
    |> cast_embed(:predictions)
    |> validate_change(:code, &DictionaryReference.validate_change/2)
    |> validate_change(:asserted_date, &validate_asserted_date/2)
  end

  defp validate_asserted_date(:asserted_date, value) do
    case DateTime.compare(value, DateTime.utc_now()) do
      :gt -> [asserted_date: "Asserted date must be in past"]
      _ -> []
    end
  end

  def fill_up_performer(%__MODULE__{performer: performer} = risk_assessment) do
    case performer do
      %Reference{identifier: identifier} ->
        display_value =
          with [{_, employee}] <- :ets.lookup(CacheHelper.get_cache_key(), "employee_#{identifier.value}") do
            first_name = employee.party.first_name
            second_name = employee.party.second_name
            last_name = employee.party.last_name

            "#{first_name} #{second_name} #{last_name}"
          else
            _ ->
              Logger.warn("Failed to fill up employee value for risk assessment")
              nil
          end

        %{
          risk_assessment
          | performer: %{
              performer
              | display_value: display_value
            }
        }

      _ ->
        risk_assessment
    end
  end
end
