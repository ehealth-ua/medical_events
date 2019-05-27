defmodule Core.Condition do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.Ecto.UUID, as: U
  alias Core.Evidence
  alias Core.Reference
  alias Core.Source
  alias Core.Stage
  alias Core.Validators.DictionaryReference
  alias Core.Validators.MaxDaysPassed
  import Ecto.Changeset
  require Logger

  def collection, do: "conditions"

  @fields_required ~w(_id patient_id primary_source context_episode_id inserted_at updated_at inserted_by updated_by)a
  @fields_optional ~w(id clinical_status verification_status onset_date asserted_date)a

  @primary_key false
  schema "conditions" do
    field(:_id, U)
    field(:id, :string, virtual: true)
    field(:clinical_status, :string)
    field(:verification_status, :string)
    field(:patient_id, :string)
    field(:onset_date, :utc_datetime)
    field(:primary_source, :boolean)
    field(:asserted_date, :utc_datetime)
    field(:inserted_by, U)
    field(:updated_by, U)
    field(:context_episode_id, U)

    embeds_one(:severity, CodeableConcept)
    embeds_one(:code, CodeableConcept)
    embeds_one(:context, Reference)
    embeds_one(:source, Source)
    embeds_one(:stage, Stage)
    embeds_many(:body_sites, CodeableConcept)
    embeds_many(:evidences, Evidence)

    timestamps(type: :utc_datetime_usec)
  end

  def create(data) do
    %__MODULE__{}
    |> changeset(set_id(data))
    |> apply_changes()
  end

  def changeset(%__MODULE__{} = condition, params) do
    condition
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:severity)
    |> cast_embed(:code)
    |> cast_embed(:body_sites)
    |> cast_embed(:source)
    |> cast_embed(:context)
    |> cast_embed(:stage)
    |> cast_embed(:evidences)
  end

  def encounter_package_changeset(
        %__MODULE__{} = condition,
        params,
        patient_id_hash,
        observations,
        encounter_id,
        client_id
      ) do
    changeset =
      condition
      |> cast(params, @fields_required ++ @fields_optional)
      |> put_id()
      |> validate_required(@fields_required)
      |> cast_embed(:severity)
      |> cast_embed(:code)
      |> cast_embed(:body_sites)

    changeset
    |> cast_embed(:source,
      required: true,
      with: &Source.report_origin_asserter_changeset(&1, &2, get_change(changeset, :primary_source), client_id)
    )
    |> cast_embed(:context,
      required: true,
      with:
        &Reference.equals_changeset(&1, &2,
          value: encounter_id,
          message: "Submitted context is not allowed for the condition"
        )
    )
    |> cast_embed(:stage)
    |> cast_embed(:evidences,
      with: &Evidence.encounter_package_changeset(&1, &2, patient_id_hash: patient_id_hash, observations: observations)
    )
    |> validate_change(:severity, &DictionaryReference.validate_change/2)
    |> validate_change(:code, &DictionaryReference.validate_change/2)
    |> validate_change(:body_sites, &DictionaryReference.validate_change/2)
    |> validate_change(:onset_date, &validate_onset_date/2)
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

  defp validate_onset_date(:onset_date, value) do
    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:condition_max_days_passed]

    if DateTime.compare(value, DateTime.utc_now()) == :gt do
      [issued: "Onset date must be in past"]
    else
      case MaxDaysPassed.validate(value, max_days_passed: max_days_passed) do
        {:error, reason} -> [issued: reason]
        _ -> []
      end
    end
  end

  def fill_up_asserter(%__MODULE__{source: source} = condition) do
    case source do
      %{asserter: asserter} when not is_nil(asserter) ->
        display_value =
          with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{asserter.identifier.value}") do
            first_name = employee.party.first_name
            second_name = employee.party.second_name
            last_name = employee.party.last_name

            "#{first_name} #{second_name} #{last_name}"
          else
            _ ->
              Logger.warn("Failed to fill up employee value for condition")
              nil
          end

        %{condition | source: %{source | asserter: %{asserter | display_value: display_value}}}

      _ ->
        condition
    end
  end
end
