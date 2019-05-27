defmodule Core.MedicationStatement do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.Ecto.UUID, as: U
  alias Core.Reference
  alias Core.Source
  alias Core.Validators.MaxDaysPassed
  import Ecto.Changeset
  require Logger

  @status_active "active"
  @status_stopped "stopped"
  @status_entered_in_error "entered_in_error"

  def status(:active), do: @status_active
  def status(:stopped), do: @status_stopped
  def status(:entered_in_error), do: @status_entered_in_error

  @fields_required ~w(id status asserted_date primary_source inserted_at updated_at inserted_by updated_by)a
  @fields_optional ~w(effective_period note dosage)a

  @primary_key false
  embedded_schema do
    field(:id, U)
    field(:status, :string)
    field(:effective_period, :string)
    field(:asserted_date, :utc_datetime)
    field(:primary_source, :boolean)
    field(:note, :string)
    field(:dosage, :string)
    field(:inserted_by, U)
    field(:updated_by, U)

    embeds_one(:based_on, Reference)
    embeds_one(:medication_code, CodeableConcept)
    embeds_one(:context, Reference)
    embeds_one(:source, Source)

    timestamps(type: :utc_datetime_usec)
  end

  def create(data) do
    %__MODULE__{}
    |> changeset(data)
    |> apply_changes()
  end

  def changeset(%__MODULE__{} = medication_statement, params) do
    medication_statement
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:based_on)
    |> cast_embed(:medication_code)
    |> cast_embed(:context)
    |> cast_embed(:source)
  end

  def encounter_package_changeset(
        %__MODULE__{} = medication_statement,
        params,
        patient_id_hash,
        encounter_id,
        client_id
      ) do
    changeset =
      medication_statement
      |> cast(params, @fields_required ++ @fields_optional)
      |> validate_required(@fields_required)
      |> cast_embed(:based_on, with: &Reference.medication_request_changeset(&1, &2, patient_id_hash: patient_id_hash))
      |> cast_embed(:medication_code, required: true)
      |> cast_embed(:context,
        required: true,
        with:
          &Reference.equals_changeset(&1, &2,
            value: encounter_id,
            message: "Submitted context is not allowed for the medication statement"
          )
      )

    changeset
    |> cast_embed(:source,
      required: true,
      with: &Source.report_origin_asserter_changeset(&1, &2, get_change(changeset, :primary_source), client_id)
    )
    |> validate_change(:asserted_date, &validate_asserted_date/2)
  end

  defp validate_asserted_date(:asserted_date, value) do
    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:medication_statement_max_days_passed]

    if DateTime.compare(value, DateTime.utc_now()) == :gt do
      [onset_date_time: "Asserted date must be in past"]
    else
      case MaxDaysPassed.validate(value, max_days_passed: max_days_passed) do
        {:error, reason} -> [asserted_date: reason]
        _ -> []
      end
    end
  end

  def fill_up_asserter(%__MODULE__{source: source} = medication_statement) do
    case source do
      %Source{asserter: asserter} ->
        display_value =
          with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{asserter.identifier.value}") do
            first_name = employee.party.first_name
            second_name = employee.party.second_name
            last_name = employee.party.last_name

            "#{first_name} #{second_name} #{last_name}"
          else
            _ ->
              Logger.warn("Failed to fill up employee value for medication statement")
              nil
          end

        %{
          medication_statement
          | source: %{
              source
              | asserter: %{
                  asserter
                  | display_value: display_value
                }
            }
        }

      _ ->
        medication_statement
    end
  end
end
