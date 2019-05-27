defmodule Core.Observation do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.Ecto.UUID, as: U
  alias Core.EffectiveAt
  alias Core.Observations.Component
  alias Core.Observations.ReferenceRange
  alias Core.Observations.Value
  alias Core.Reference
  alias Core.Source
  alias Core.Validators.DictionaryReference
  alias Core.Validators.MaxDaysPassed
  import Ecto.Changeset
  require Logger

  def collection, do: "observations"

  @fields_required ~w(
    _id
    status
    patient_id
    issued
    primary_source
    inserted_at
    updated_at
    inserted_by
    updated_by
  )a

  @fields_optional ~w(comment context_episode_id)a

  @status_valid "valid"
  @status_entered_in_error "entered_in_error"

  def status(:valid), do: @status_valid
  def status(:entered_in_error), do: @status_entered_in_error

  @primary_key false
  schema "observations" do
    field(:_id, U)
    field(:id, :string, virtual: true)
    field(:status, :string)
    field(:patient_id, :string)
    field(:issued, :utc_datetime)
    field(:primary_source, :boolean)
    field(:comment, :string)
    field(:context_episode_id, U)
    field(:inserted_by, U)
    field(:updated_by, U)

    embeds_many(:based_on, Reference)
    embeds_many(:categories, CodeableConcept)
    embeds_one(:code, CodeableConcept)
    embeds_one(:context, Reference)
    embeds_one(:diagnostic_report, Reference)
    embeds_one(:effective_at, EffectiveAt)
    embeds_one(:source, Source)
    embeds_one(:value, Value)
    embeds_one(:interpretation, CodeableConcept)
    embeds_one(:body_site, CodeableConcept)
    embeds_one(:method, CodeableConcept)
    embeds_one(:reaction_on, Reference)
    embeds_many(:reference_ranges, ReferenceRange)
    embeds_many(:components, Component)

    timestamps(type: :utc_datetime_usec)
  end

  def create(data) do
    %__MODULE__{}
    |> changeset(set_id(data))
    |> apply_changes()
  end

  def changeset(%__MODULE__{} = observation, params) do
    observation
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:categories)
    |> cast_embed(:code)
    |> cast_embed(:context)
    |> cast_embed(:diagnostic_report)
    |> cast_embed(:effective_at)
    |> cast_embed(:source)
    |> cast_embed(:value)
    |> cast_embed(:interpretation)
    |> cast_embed(:body_site)
    |> cast_embed(:method)
    |> cast_embed(:reference_ranges)
    |> cast_embed(:components)
    |> cast_embed(:based_on)
    |> cast_embed(:reaction_on)
  end

  def encounter_package_changeset(
        %__MODULE__{} = observation,
        params,
        patient_id_hash,
        diagnostic_reports,
        encounter_id,
        client_id
      ) do
    changeset =
      observation
      |> cast(params, @fields_required ++ @fields_optional ++ [:id])
      |> put_id()
      |> validate_required(@fields_required)
      |> cast_embed(:categories, required: true)
      |> cast_embed(:code, required: true)
      |> cast_embed(:context,
        with:
          &Reference.equals_changeset(&1, &2,
            value: encounter_id,
            message: "Submitted context is not allowed for the observation"
          )
      )
      |> cast_embed(:diagnostic_report,
        with:
          &Reference.diagnostic_report_changeset(&1, &2,
            patient_id_hash: patient_id_hash,
            diagnostic_reports: diagnostic_reports,
            payload_only: true
          )
      )
      |> cast_embed(:effective_at, required: true)

    changeset
    |> cast_embed(:source,
      required: true,
      with:
        &Source.report_origin_performer_changeset(
          &1,
          &2,
          get_change(changeset, :primary_source),
          client_id
        )
    )
    |> cast_embed(:value, required: true)
    |> cast_embed(:interpretation)
    |> cast_embed(:body_site)
    |> cast_embed(:method)
    |> cast_embed(:reference_ranges)
    |> cast_embed(:components)
    |> cast_embed(:reaction_on)
    |> validate_change(:categories, &DictionaryReference.validate_change/2)
    |> validate_change(:code, &DictionaryReference.validate_change/2)
    |> validate_change(:interpretation, &DictionaryReference.validate_change/2)
    |> validate_change(:body_site, &DictionaryReference.validate_change/2)
    |> validate_change(:method, &DictionaryReference.validate_change/2)
    |> validate_change(:issued, &validate_issued/2)
  end

  def diagnostic_report_package_changeset(
        %__MODULE__{} = observation,
        params,
        diagnostic_report_id,
        client_id
      ) do
    changeset =
      observation
      |> cast(params, @fields_required ++ @fields_optional ++ [:id])
      |> put_id()
      |> validate_required(@fields_required)
      |> cast_embed(:categories, required: true)
      |> cast_embed(:code, required: true)
      |> cast_embed(:diagnostic_report,
        with:
          &Reference.equals_changeset(&1, &2,
            value: diagnostic_report_id,
            message: "Submitted diagnostic report is not allowed for the observation"
          )
      )
      |> cast_embed(:effective_at, required: true)

    changeset
    |> cast_embed(:source,
      required: true,
      with:
        &Source.report_origin_performer_changeset(
          &1,
          &2,
          get_change(changeset, :primary_source),
          client_id
        )
    )
    |> cast_embed(:value, required: true)
    |> cast_embed(:interpretation)
    |> cast_embed(:body_site)
    |> cast_embed(:method)
    |> cast_embed(:reference_ranges)
    |> cast_embed(:components)
    |> cast_embed(:reaction_on)
    |> validate_change(:categories, &DictionaryReference.validate_change/2)
    |> validate_change(:code, &DictionaryReference.validate_change/2)
    |> validate_change(:interpretation, &DictionaryReference.validate_change/2)
    |> validate_change(:body_site, &DictionaryReference.validate_change/2)
    |> validate_change(:method, &DictionaryReference.validate_change/2)
    |> validate_change(:issued, &validate_issued/2)
  end

  defp set_id(params) do
    if params["_id"] do
      Map.put(params, "id", params["_id"])
    else
      Map.put(params, "_id", params["id"])
    end
  end

  defp put_id(changeset) do
    put_change(changeset, :_id, get_change(changeset, :id))
  end

  defp validate_issued(:issued, value) do
    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:observation_max_days_passed]

    if DateTime.compare(value, DateTime.utc_now()) == :gt do
      [issued: "Issued must be in past"]
    else
      case MaxDaysPassed.validate(value, max_days_passed: max_days_passed) do
        {:error, reason} -> [issued: reason]
        _ -> []
      end
    end
  end

  def fill_up_performer(%__MODULE__{source: source} = observation) do
    case source do
      %Source{performer: performer} = source when not is_nil(performer) ->
        display_value =
          with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{performer.identifier.value}") do
            first_name = employee.party.first_name
            second_name = employee.party.second_name
            last_name = employee.party.last_name

            "#{first_name} #{second_name} #{last_name}"
          else
            _ ->
              Logger.warn("Failed to fill up employee value for observation")
              nil
          end

        %{observation | source: %{source | performer: %{performer | display_value: display_value}}}

      _ ->
        observation
    end
  end
end
