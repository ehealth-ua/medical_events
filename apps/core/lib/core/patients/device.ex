defmodule Core.Device do
  @moduledoc false

  use Ecto.Schema

  alias Core.CacheHelper
  alias Core.CodeableConcept
  alias Core.Ecto.UUID, as: U
  alias Core.Period
  alias Core.Reference
  alias Core.Source
  alias Core.Validators.MaxDaysPassed
  import Ecto.Changeset
  require Logger

  @status_active "active"
  @status_inactive "inactive"
  @status_entered_in_error "entered_in_error"
  @status_unknown "unknown"

  def status(:active), do: @status_active
  def status(:inactive), do: @status_inactive
  def status(:entered_in_error), do: @status_entered_in_error
  def status(:unknown), do: @status_unknown

  @fields_required ~w(id status asserted_date primary_source inserted_at updated_at inserted_by updated_by)a
  @fields_optional ~w(lot_number manufacturer manufacture_date expiration_date model version note)a

  @primary_key false
  embedded_schema do
    field(:id, U)
    field(:status, :string)
    field(:asserted_date, :utc_datetime)
    field(:primary_source, :boolean)
    field(:lot_number, :string)
    field(:manufacturer, :string)
    field(:manufacture_date, :utc_datetime)
    field(:expiration_date, :utc_datetime)
    field(:model, :string)
    field(:version, :string)
    field(:note, :string)
    field(:inserted_by, U)
    field(:updated_by, U)

    embeds_one(:usage_period, Period)
    embeds_one(:context, Reference)
    embeds_one(:source, Source)
    embeds_one(:type, CodeableConcept)

    timestamps(type: :utc_datetime_usec)
  end

  def create(data) do
    %__MODULE__{}
    |> changeset(data)
    |> apply_changes()
  end

  def changeset(%__MODULE__{} = device, params) do
    device
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:usage_period)
    |> cast_embed(:context)
    |> cast_embed(:source)
    |> cast_embed(:type)
  end

  def encounter_package_changeset(%__MODULE__{} = device, params, encounter_id, client_id) do
    changeset =
      device
      |> cast(params, @fields_required ++ @fields_optional)
      |> validate_required(@fields_required)
      |> cast_embed(:usage_period, required: true)
      |> cast_embed(:context,
        required: true,
        with:
          &Reference.equals_changeset(&1, &2,
            value: encounter_id,
            message: "Submitted context is not allowed for the device"
          )
      )

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
    |> cast_embed(:type, required: true)
    |> validate_change(:asserted_date, &validate_asserted_date/2)
  end

  defp validate_asserted_date(:asserted_date, value) do
    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:device_max_days_passed]

    if DateTime.compare(value, DateTime.utc_now()) == :gt do
      [onset_date_time: "Asserted date must be in past"]
    else
      case MaxDaysPassed.validate(value, max_days_passed: max_days_passed) do
        {:error, reason} -> [asserted_date: reason]
        _ -> []
      end
    end
  end

  def fill_up_asserter(%__MODULE__{source: source} = device) do
    case source do
      %{asserter: asserter} when not is_nil(asserter) ->
        display_value =
          with [{_, employee}] <- :ets.lookup(CacheHelper.get_cache_key(), "employee_#{asserter.identifier.value}") do
            first_name = employee.party.first_name
            second_name = employee.party.second_name
            last_name = employee.party.last_name

            "#{first_name} #{second_name} #{last_name}"
          else
            _ ->
              Logger.warn("Failed to fill up employee value for device")
              nil
          end

        %{device | source: %{source | asserter: %{asserter | display_value: display_value}}}

      _ ->
        device
    end
  end
end
