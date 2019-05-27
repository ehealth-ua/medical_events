defmodule Core.Immunization do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.Ecto.UUID, as: U
  alias Core.Observations.Values.Quantity
  alias Core.Patients.Immunizations.Explanation
  alias Core.Patients.Immunizations.Reaction
  alias Core.Patients.Immunizations.VaccinationProtocol
  alias Core.Reference
  alias Core.Source
  alias Core.Validators.DictionaryReference
  alias Core.Validators.MaxDaysPassed
  import Ecto.Changeset
  require Logger

  @fields_required ~w(id status date primary_source inserted_by updated_by inserted_at updated_at)a
  @fields_optional ~w(not_given manufacturer lot_number expiration_date)a

  @status_completed "completed"
  @status_entered_in_error "entered_in_error"

  def status(:completed), do: @status_completed
  def status(:entered_in_error), do: @status_entered_in_error

  @primary_key false
  embedded_schema do
    field(:id, U)
    field(:status, :string)
    field(:not_given, :boolean)
    field(:date, :utc_datetime)
    field(:primary_source, :boolean)
    field(:manufacturer, :string)
    field(:lot_number, :string)
    field(:expiration_date, :utc_datetime)
    field(:inserted_by, U)
    field(:updated_by, U)

    embeds_one(:vaccine_code, CodeableConcept)
    embeds_one(:context, Reference)
    embeds_one(:source, Source)
    embeds_one(:legal_entity, Reference)
    embeds_one(:site, CodeableConcept)
    embeds_one(:route, CodeableConcept)
    embeds_one(:dose_quantity, Quantity)
    embeds_one(:explanation, Explanation)
    embeds_many(:reactions, Reaction, on_replace: :delete)
    embeds_many(:vaccination_protocols, VaccinationProtocol)

    timestamps(type: :utc_datetime_usec)
  end

  def create(data) do
    %__MODULE__{}
    |> changeset(data)
    |> apply_changes()
  end

  def changeset(%__MODULE__{} = immunization, params) do
    immunization
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:vaccine_code)
    |> cast_embed(:context)
    |> cast_embed(:source)
    |> cast_embed(:legal_entity)
    |> cast_embed(:site)
    |> cast_embed(:dose_quantity)
    |> cast_embed(:explanation)
    |> cast_embed(:reactions)
  end

  def encounter_package_changeset(
        %__MODULE__{} = immunization,
        params,
        patient_id_hash,
        observations,
        encounter_id,
        client_id
      ) do
    changeset =
      immunization
      |> cast(params, @fields_required ++ @fields_optional)
      |> validate_required(@fields_required)
      |> cast_embed(:vaccine_code, required: true)
      |> cast_embed(:context,
        required: true,
        with:
          &Reference.equals_changeset(&1, &2,
            value: encounter_id,
            message: "Submitted context is not allowed for the immunization"
          )
      )

    changeset
    |> cast_embed(:source,
      required: true,
      with: &Source.report_origin_performer_changeset(&1, &2, get_change(changeset, :primary_source), client_id)
    )
    |> cast_embed(:legal_entity)
    |> cast_embed(:site)
    |> cast_embed(:dose_quantity)
    |> cast_embed(:explanation)
    |> cast_embed(:reactions, with: &Reaction.encounter_package_changeset(&1, &2, patient_id_hash, observations))
    |> validate_change(:vaccine_code, &DictionaryReference.validate_change/2)
    |> validate_change(:site, &DictionaryReference.validate_change/2)
    |> validate_change(:route, &DictionaryReference.validate_change/2)
    |> validate_change(:date, &validate_date/2)
  end

  def reactions_update_changeset(%__MODULE__{} = immunization, params, patient_id_hash, observations) do
    immunization
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:reactions, with: &Reaction.encounter_package_changeset(&1, &2, patient_id_hash, observations))
  end

  defp validate_date(:date, value) do
    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:immunization_max_days_passed]

    if DateTime.compare(value, DateTime.utc_now()) == :gt do
      [issued: "Date must be in past"]
    else
      case MaxDaysPassed.validate(value, max_days_passed: max_days_passed) do
        {:error, reason} -> [issued: reason]
        _ -> []
      end
    end
  end

  def fill_up_performer(%__MODULE__{source: %Source{performer: performer}} = immunization) do
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
              Logger.warn("Failed to fill up employee value for immunization")
              nil
          end

        %{
          immunization
          | source: %{
              immunization.source
              | performer: %{
                  performer
                  | display_value: display_value
                }
            }
        }

      _ ->
        immunization
    end
  end

  def fill_up_performer(immunization), do: immunization
end
