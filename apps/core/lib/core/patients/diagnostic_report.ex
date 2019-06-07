defmodule Core.DiagnosticReport do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.DiagnosticReports.Source
  alias Core.Ecto.UUID, as: U
  alias Core.EffectiveAt
  alias Core.Encounter
  alias Core.Executor
  alias Core.Patients.Encounters
  alias Core.Reference
  alias Core.ServiceRequest
  alias Core.ServiceRequests
  alias Core.Services
  alias Core.Validators.DictionaryReference
  alias Core.Validators.MaxDaysPassed
  import Ecto.Changeset
  require Logger

  @diagnostic_procedure_category "diagnostic_procedure"
  @imaging_category "imaging"

  @status_final "final"
  @status_entered_in_error "entered_in_error"

  def status(:final), do: @status_final
  def status(:entered_in_error), do: @status_entered_in_error

  @fields_required ~w(id status inserted_by updated_by inserted_at updated_at issued primary_source)a
  @fields_optional ~w(conclusion signed_content_links explanatory_letter)a

  @primary_key false
  embedded_schema do
    field(:id, U)
    field(:status, :string)
    field(:issued, :utc_datetime)
    field(:primary_source, :boolean)
    field(:conclusion, :string)
    field(:signed_content_links, {:array, :string})
    field(:explanatory_letter, :string)
    field(:inserted_by, U)
    field(:updated_by, U)

    embeds_one(:based_on, Reference)
    embeds_one(:origin_episode, Reference)
    embeds_many(:category, CodeableConcept)
    embeds_one(:code, Reference)
    embeds_one(:encounter, Reference)
    embeds_one(:effective, EffectiveAt)
    embeds_one(:source, Source)
    embeds_one(:recorded_by, Reference)
    embeds_one(:results_interpreter, Executor)
    embeds_one(:managing_organization, Reference)
    embeds_one(:conclusion_code, CodeableConcept)
    embeds_one(:cancellation_reason, CodeableConcept)

    timestamps(type: :utc_datetime_usec)
  end

  def create(data) do
    %__MODULE__{}
    |> changeset(data)
    |> apply_changes()
  end

  def changeset(%__MODULE__{} = diagnostic_report, params) do
    diagnostic_report
    |> cast(params, @fields_required ++ @fields_optional)
    |> cast_embed(:based_on)
    |> cast_embed(:origin_episode)
    |> cast_embed(:category)
    |> cast_embed(:code, required: true)
    |> cast_embed(:encounter)
    |> cast_embed(:effective)
    |> cast_embed(:source)
    |> cast_embed(:recorded_by)
    |> cast_embed(:results_interpreter)
    |> cast_embed(:managing_organization)
    |> cast_embed(:conclusion_code)
    |> cast_embed(:cancellation_reason)
  end

  def encounter_package_changeset(
        %__MODULE__{} = diagnostic_report,
        params,
        client_id,
        encounter_id,
        observations
      ) do
    changeset =
      diagnostic_report
      |> cast(params, @fields_required ++ @fields_optional)
      |> validate_required(@fields_required)
      |> cast_embed(:origin_episode)
      |> cast_embed(:category)
      |> cast_embed(:code,
        required: true,
        with: &Reference.service_changeset(&1, &2, observations)
      )
      |> cast_embed(:encounter, with: &Reference.equals_changeset(&1, &2, value: encounter_id))
      |> cast_embed(:effective)

    primary_source = get_change(changeset, :primary_source)

    changeset =
      changeset
      |> cast_embed(:recorded_by,
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
      |> validate_managing_organization(primary_source, client_id)
      |> cast_embed(:conclusion_code)
      |> cast_embed(:cancellation_reason)
      |> validate_change(:category, &DictionaryReference.validate_change/2)
      |> validate_change(:conclusion_code, &DictionaryReference.validate_change/2)
      |> validate_change(:cancellation_reason, &DictionaryReference.validate_change/2)
      |> validate_change(:issued, &validate_issued/2)

    service_id = changeset |> get_change(:code) |> get_change(:identifier) |> get_change(:value)

    changeset
    |> cast_embed(:based_on,
      with:
        &Reference.service_request_changeset(&1, &2,
          client_id: client_id,
          datetime: DateTime.utc_now(),
          service_id: service_id
        )
    )
    |> validate_source(client_id)
    |> validate_results_interpreter(client_id, service_id)
    |> validate_conclusion(service_id)
  end

  def diagnostic_report_package_changeset(%__MODULE__{} = diagnostic_report, params, client_id, observations) do
    changeset =
      diagnostic_report
      |> cast(params, @fields_required ++ @fields_optional)
      |> validate_required(@fields_required)
      |> cast_embed(:origin_episode)
      |> cast_embed(:category)
      |> cast_embed(:code,
        required: true,
        with: &Reference.service_changeset(&1, &2, observations)
      )
      |> cast_embed(:effective)

    primary_source = get_change(changeset, :primary_source)

    changeset =
      changeset
      |> cast_embed(:recorded_by,
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
      |> validate_managing_organization(primary_source, client_id)
      |> cast_embed(:conclusion_code)
      |> cast_embed(:cancellation_reason)
      |> validate_change(:category, &DictionaryReference.validate_change/2)
      |> validate_change(:conclusion_code, &DictionaryReference.validate_change/2)
      |> validate_change(:cancellation_reason, &DictionaryReference.validate_change/2)
      |> validate_change(:issued, &validate_issued/2)

    service_id = changeset |> get_change(:code) |> get_change(:identifier) |> get_change(:value)

    changeset
    |> cast_embed(:based_on,
      with:
        &Reference.service_request_changeset(&1, &2,
          client_id: client_id,
          datetime: DateTime.utc_now(),
          service_id: service_id
        )
    )
    |> validate_source(client_id)
    |> validate_results_interpreter(client_id, service_id)
    |> validate_conclusion(service_id)
  end

  defp validate_issued(:issued, value) do
    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:diagnostic_report_max_days_passed]

    if DateTime.compare(value, DateTime.utc_now()) == :gt do
      [issued: "Issued must be in past"]
    else
      case MaxDaysPassed.validate(value, max_days_passed: max_days_passed) do
        {:error, reason} -> [issued: reason]
        _ -> []
      end
    end
  end

  defp validate_source(changeset, client_id) do
    primary_source = get_change(changeset, :primary_source)

    changeset =
      cast_embed(changeset, :source, with: &Source.encounter_package_changeset(&1, &2, primary_source, client_id))

    if primary_source do
      changeset
    else
      source = get_change(changeset, :source)

      if source && !get_change(source, :report_origin) && !get_change(source, :performer) do
        add_error(changeset, :source, "report_origin or performer with type text must be filled")
      else
        changeset
      end
    end
  end

  defp validate_results_interpreter(changeset, client_id, service_id) do
    primary_source = get_change(changeset, :primary_source)

    if primary_source do
      with {:ok, %{category: category}} <- Services.get_service(service_id),
           true <- category in [@diagnostic_procedure_category, @imaging_category] do
        required_message =
          "results_interpreter with type reference must be filled when service category" <>
            " is #{@diagnostic_procedure_category} or #{@imaging_category}"

        cast_embed(
          changeset,
          :results_interpreter,
          required: true,
          required_message: required_message,
          with: &Executor.reference_changeset(&1, &2, client_id, required_message)
        )
      else
        _ -> changeset
      end
    else
      cast_embed(changeset, :results_interpreter, with: &Executor.results_interpreter_text_changeset/2)
    end
  end

  defp validate_conclusion(changeset, service_id) do
    conclusion = get_change(changeset, :conclusion)

    with {:ok, %{category: category}} <- Services.get_service(service_id),
         true <- category in [@diagnostic_procedure_category, @imaging_category] do
      if conclusion do
        changeset
      else
        add_error(
          changeset,
          :conclusion,
          "Must be filled when service category is #{@diagnostic_procedure_category} or #{@imaging_category}"
        )
      end
    else
      _ -> changeset
    end
  end

  defp validate_managing_organization(changeset, true, client_id) do
    cast_embed(changeset, :managing_organization,
      required: true,
      with: &Reference.legal_entity_changeset(&1, &2, client_id)
    )
  end

  defp validate_managing_organization(changeset, _, _) do
    cast_embed(changeset, :managing_organization)
  end

  def fill_up_performer(%__MODULE__{source: %Source{performer: performer} = source} = diagnostic_report) do
    case performer do
      %{reference: reference} when not is_nil(reference) ->
        display_value =
          with [{_, employee}] <-
                 :ets.lookup(:message_cache, "employee_#{reference.identifier.value}") do
            first_name = employee.party.first_name
            second_name = employee.party.second_name
            last_name = employee.party.last_name

            "#{first_name} #{second_name} #{last_name}"
          else
            _ ->
              Logger.warn("Failed to fill up performer value for diagnostic report")
              nil
          end

        %{
          diagnostic_report
          | source: %{
              source
              | performer: %{
                  performer
                  | reference: %{
                      reference
                      | display_value: display_value
                    }
                }
            }
        }

      _ ->
        diagnostic_report
    end
  end

  def fill_up_performer(diagnostic_report), do: diagnostic_report

  def fill_up_recorded_by(%__MODULE__{recorded_by: recorded_by} = diagnostic_report) do
    case recorded_by do
      %Reference{} ->
        display_value =
          with [{_, employee}] <-
                 :ets.lookup(:message_cache, "employee_#{recorded_by.identifier.value}") do
            first_name = employee.party.first_name
            second_name = employee.party.second_name
            last_name = employee.party.last_name

            "#{first_name} #{second_name} #{last_name}"
          else
            _ ->
              Logger.warn("Failed to fill up recorded_by value for diagnostic report")
              nil
          end

        %{
          diagnostic_report
          | recorded_by: %{recorded_by | display_value: display_value}
        }

      _ ->
        diagnostic_report
    end
  end

  def fill_up_results_interpreter(%__MODULE__{results_interpreter: results_interpreter} = diagnostic_report) do
    case results_interpreter do
      %Executor{reference: reference} ->
        display_value =
          with [{_, employee}] <-
                 :ets.lookup(:message_cache, "employee_#{reference.identifier.value}") do
            first_name = employee.party.first_name
            second_name = employee.party.second_name
            last_name = employee.party.last_name

            "#{first_name} #{second_name} #{last_name}"
          else
            _ ->
              Logger.warn("Failed to fill up performer value for diagnostic report")
              nil
          end

        %{
          diagnostic_report
          | results_interpreter: %{
              results_interpreter
              | reference: %{reference | display_value: display_value}
            }
        }

      _ ->
        diagnostic_report
    end
  end

  def fill_up_managing_organization(%__MODULE__{managing_organization: managing_organization} = diagnostic_report) do
    case managing_organization do
      %Reference{} ->
        display_value =
          with [{_, legal_entity}] <-
                 :ets.lookup(:message_cache, "legal_entity_#{managing_organization.identifier.value}") do
            Map.get(legal_entity, :public_name)
          else
            _ ->
              Logger.warn("Failed to fill up legal_entity value for diagnostic report")
              nil
          end

        %{
          diagnostic_report
          | managing_organization: %{
              managing_organization
              | display_value: display_value
            }
        }

      _ ->
        diagnostic_report
    end
  end

  def fill_up_origin_episode(%__MODULE__{based_on: based_on} = diagnostic_report, patient_id_hash) do
    case based_on do
      nil ->
        diagnostic_report

      _ ->
        origin_episode =
          with {:ok, %ServiceRequest{context: context}} <-
                 ServiceRequests.get_by_id(based_on.identifier.value, projection: [context: true]),
               {:ok, %Encounter{episode: episode}} <-
                 Encounters.get_by_id(patient_id_hash, to_string(context.identifier.value)) do
            episode
          end

        %{diagnostic_report | origin_episode: origin_episode}
    end
  end
end
