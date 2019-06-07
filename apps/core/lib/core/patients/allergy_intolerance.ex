defmodule Core.AllergyIntolerance do
  @moduledoc false

  use Ecto.Schema

  alias Core.CacheHelper
  alias Core.CodeableConcept
  alias Core.Ecto.UUID, as: U
  alias Core.Reference
  alias Core.Source
  alias Core.Validators.DictionaryReference
  alias Core.Validators.MaxDaysPassed
  import Ecto.Changeset
  require Logger

  @clinical_status_active "active"
  @clinical_status_inactive "inactive"
  @clinical_status_resolved "resolved"

  @verification_status_confirmed "confirmed"
  @verification_status_refuted "refuted"
  @verification_status_entered_in_error "entered_in_error"

  def clinical_status(:active), do: @clinical_status_active
  def clinical_status(:inactive), do: @clinical_status_inactive
  def clinical_status(:resolved), do: @clinical_status_resolved

  def verification_status(:confirmed), do: @verification_status_confirmed
  def verification_status(:refuted), do: @verification_status_refuted
  def verification_status(:entered_in_error), do: @verification_status_entered_in_error

  @fields_required ~w(
    id
    clinical_status
    verification_status
    type
    category
    criticality
    onset_date_time
    asserted_date
    primary_source
    inserted_at
    updated_at
    inserted_by
    updated_by
  )a
  @fields_optional ~w(last_occurrence)a

  @primary_key false
  embedded_schema do
    field(:id, U)
    field(:clinical_status, :string)
    field(:verification_status, :string)
    field(:type, :string)
    field(:category, :string)
    field(:criticality, :string)
    field(:onset_date_time, :utc_datetime)
    field(:asserted_date, :utc_datetime)
    field(:primary_source, :boolean)
    field(:last_occurrence, :utc_datetime)
    field(:inserted_by, U)
    field(:updated_by, U)

    embeds_one(:code, CodeableConcept)
    embeds_one(:source, Source)
    embeds_one(:context, Reference)

    timestamps(type: :utc_datetime_usec)
  end

  def create(data) do
    %__MODULE__{}
    |> changeset(data)
    |> apply_changes()
  end

  def changeset(%__MODULE__{} = allergy_intolerance, params) do
    allergy_intolerance
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:code)
    |> cast_embed(:source)
    |> cast_embed(:context)
  end

  def encounter_package_changeset(
        %__MODULE__{} = allergy_intolerance,
        params,
        encounter_id,
        client_id
      ) do
    changeset =
      allergy_intolerance
      |> cast(params, @fields_required ++ @fields_optional)
      |> validate_required(@fields_required)
      |> cast_embed(:code, required: true)

    changeset
    |> cast_embed(:source,
      required: true,
      with:
        &Source.report_origin_asserter_changeset(
          &1,
          &2,
          get_change(changeset, :primary_source),
          client_id
        )
    )
    |> cast_embed(:context,
      required: true,
      with:
        &Reference.equals_changeset(&1, &2,
          value: encounter_id,
          message: "Submitted context is not allowed for the allergy intolerance"
        )
    )
    |> validate_change(:code, &DictionaryReference.validate_change/2)
    |> validate_change(:onset_date_time, &validate_onset_date_time/2)
    |> validate_change(:last_occurrence, &validate_last_occurrence/2)
    |> validate_change(:asserted_date, &validate_asserted_date/2)
  end

  defp validate_last_occurrence(:last_occurrence, value) do
    case DateTime.compare(value, DateTime.utc_now()) do
      :gt -> [last_occurrence: "Last occurrence must be in past"]
      _ -> []
    end
  end

  defp validate_asserted_date(:asserted_date, value) do
    case DateTime.compare(value, DateTime.utc_now()) do
      :gt -> [asserted_date: "Asserted date must be in past"]
      _ -> []
    end
  end

  defp validate_onset_date_time(:onset_date_time, value) do
    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:allergy_intolerance_max_days_passed]

    if DateTime.compare(value, DateTime.utc_now()) == :gt do
      [onset_date_time: "Onset date time must be in past"]
    else
      case MaxDaysPassed.validate(value, max_days_passed: max_days_passed) do
        {:error, reason} -> [onset_date_time: reason]
        _ -> []
      end
    end
  end

  def fill_up_asserter(%__MODULE__{source: source} = allergy_intolerance) do
    case source do
      %Source{asserter: asserter} when not is_nil(asserter) ->
        with [{_, employee}] <- :ets.lookup(CacheHelper.get_cache_key(), "employee_#{asserter.identifier.value}") do
          first_name = employee.party.first_name
          second_name = employee.party.second_name
          last_name = employee.party.last_name

          %{
            allergy_intolerance
            | source: %{
                allergy_intolerance.source
                | asserter: %{
                    asserter
                    | display_value: "#{first_name} #{second_name} #{last_name}"
                  }
              }
          }
        else
          _ ->
            Logger.warn("Failed to fill up employee value for allergy_intolerance")
            allergy_intolerance
        end

      _ ->
        allergy_intolerance
    end
  end
end
