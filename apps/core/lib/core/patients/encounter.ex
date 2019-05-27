defmodule Core.Encounter do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.Coding
  alias Core.Diagnosis
  alias Core.Ecto.UUID, as: U
  alias Core.Episode
  alias Core.Reference
  alias Core.StatusHistory
  alias Core.Validators.DiagnosesCode
  alias Core.Validators.DiagnosesRole
  alias Core.Validators.DictionaryReference
  alias Core.Validators.MaxDaysPassed
  alias Ecto.Changeset
  import Ecto.Changeset
  require Logger

  @status_finished "finished"
  @status_entered_in_error "entered_in_error"

  def status(:finished), do: @status_finished
  def status(:entered_in_error), do: @status_entered_in_error

  @fields_required ~w(id status date inserted_at updated_at inserted_by updated_by)a
  @fields_optional ~w(signed_content_links explanatory_letter prescriptions)a

  @primary_key false
  embedded_schema do
    field(:id, U)
    field(:status, :string)
    field(:date, :utc_datetime)
    field(:explanatory_letter, :string)
    field(:signed_content_links, {:array, :string})
    field(:prescriptions, :string)
    field(:inserted_by, U)
    field(:updated_by, U)

    embeds_one(:class, Coding)
    embeds_one(:type, CodeableConcept)
    embeds_one(:incoming_referral, Reference)
    embeds_many(:status_history, StatusHistory)
    embeds_many(:reasons, CodeableConcept)
    embeds_many(:diagnoses, Diagnosis)
    embeds_one(:service_provider, Reference)
    embeds_one(:division, Reference)
    embeds_many(:actions, CodeableConcept)
    embeds_one(:performer, Reference)
    embeds_one(:episode, Reference)
    embeds_one(:visit, Reference)
    embeds_one(:cancellation_reason, CodeableConcept)
    embeds_many(:supporting_info, Reference)

    timestamps(type: :utc_datetime_usec)
  end

  def create(data) do
    %__MODULE__{}
    |> changeset(data)
    |> apply_changes()
  end

  def changeset(%__MODULE__{} = encounter, params) do
    encounter
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:class)
    |> cast_embed(:type)
    |> cast_embed(:incoming_referral)
    |> cast_embed(:status_history)
    |> cast_embed(:reasons)
    |> cast_embed(:diagnoses)
    |> cast_embed(:service_provider)
    |> cast_embed(:division)
    |> cast_embed(:actions)
    |> cast_embed(:performer)
    |> cast_embed(:episode)
    |> cast_embed(:visit)
    |> cast_embed(:cancellation_reason)
    |> cast_embed(:supporting_info)
  end

  def encounter_package_changeset(
        %__MODULE__{} = encounter,
        params,
        patient_id_hash,
        client_id,
        visit,
        conditions
      ) do
    encounter
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:class, required: true)
    |> cast_embed(:type, required: true)
    |> cast_embed(:incoming_referral,
      with:
        &Reference.service_request_changeset(&1, &2,
          client_id: client_id,
          datetime: DateTime.utc_now()
        )
    )
    |> cast_embed(:status_history)
    |> cast_embed(:reasons, required: true)
    |> cast_embed(:diagnoses,
      required: true,
      with: &Diagnosis.encounter_changeset(&1, &2, patient_id_hash, conditions)
    )
    |> cast_embed(:service_provider)
    |> cast_embed(:division,
      with:
        &Reference.division_changeset(&1, &2,
          status: "ACTIVE",
          legal_entity_id: client_id,
          messages: [
            status: "Division is not active",
            legal_entity_id: "User is not allowed to create encouners for this division"
          ]
        )
    )
    |> cast_embed(:actions, required: true)
    |> cast_embed(:performer,
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
    |> cast_embed(:episode,
      required: true,
      with:
        &Reference.episode_changeset(&1, &2,
          client_id: client_id,
          status: Episode.status(:active),
          patient_id_hash: patient_id_hash
        )
    )
    |> cast_embed(:visit,
      required: true,
      with: &Reference.visit_changeset(&1, &2, visit: visit, patient_id_hash: patient_id_hash)
    )
    |> cast_embed(:cancellation_reason)
    |> cast_embed(:supporting_info,
      with: &Reference.supporting_info_changeset(&1, &2, patient_id_hash: patient_id_hash)
    )
    |> validate_change(:class, &DictionaryReference.validate_change/2)
    |> validate_change(:type, &DictionaryReference.validate_change/2)
    |> validate_change(:reasons, &DictionaryReference.validate_change/2)
    |> validate_change(:actions, &DictionaryReference.validate_change/2)
    |> validate_change(:cancellation_reason, &DictionaryReference.validate_change/2)
    |> validate_diagnoses()
    |> validate_change(:date, &validate_date/2)
  end

  defp validate_diagnoses(changeset) do
    code = changeset |> get_change(:class) |> get_change(:code)

    validate_change(changeset, :diagnoses, fn field, value ->
      value = Enum.map(value, &Changeset.apply_changes/1)

      errors =
        case DiagnosesRole.validate(value,
               type: "primary",
               message: "Encounter must have at least one chief complaint"
             ) do
          :ok -> []
          {:error, message} -> Keyword.put([], field, message)
        end

      value
      |> Enum.with_index()
      |> Enum.reduce(errors, fn {v, k}, acc ->
        with :ok <- DiagnosesCode.validate(v, code: code) do
          acc
        else
          {:error, message} ->
            Keyword.put(acc, :"#{field}[#{k}]", message)
        end
      end)
    end)
  end

  defp validate_date(:date, value) do
    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:encounter_max_days_passed]

    if DateTime.compare(value, DateTime.utc_now()) == :gt do
      [issued: "Date must be in past"]
    else
      case MaxDaysPassed.validate(value, max_days_passed: max_days_passed) do
        {:error, reason} -> [issued: reason]
        _ -> []
      end
    end
  end

  def fill_up_performer(%__MODULE__{performer: performer} = encounter) do
    case performer do
      %Reference{} ->
        display_value =
          with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{performer.identifier.value}") do
            first_name = employee.party.first_name
            second_name = employee.party.second_name
            last_name = employee.party.last_name

            "#{first_name} #{second_name} #{last_name}"
          else
            _ ->
              Logger.warn("Failed to fill up employee value for encounter")
              nil
          end

        %{encounter | performer: %{performer | display_value: display_value}}

      _ ->
        encounter
    end
  end

  def fill_up_diagnoses_codes(%__MODULE__{diagnoses: diagnoses} = encounter) do
    diagnoses =
      Enum.map(diagnoses, fn diagnosis ->
        with [{_, condition}] <-
               :ets.lookup(:message_cache, "condition_#{diagnosis.condition.identifier.value}") do
          %{diagnosis | code: Map.get(condition, "code")}
        end
      end)

    %{encounter | diagnoses: diagnoses}
  end
end
