defmodule Core.Identifier do
  @moduledoc false

  use Ecto.Schema
  alias Core.CodeableConcept
  alias Core.Ecto.IdentifierValue
  alias Core.Validators.ConditionContext
  alias Core.Validators.DiagnosisCondition
  alias Core.Validators.DiagnosticReportContext
  alias Core.Validators.DiagnosticReportReference
  alias Core.Validators.Division
  alias Core.Validators.Drfo
  alias Core.Validators.Employee
  alias Core.Validators.EncounterReference
  alias Core.Validators.EpisodeReference
  alias Core.Validators.LegalEntity
  alias Core.Validators.MedicationRequestReference
  alias Core.Validators.ObservationContext
  alias Core.Validators.ObservationReference
  alias Core.Validators.ServiceGroupReference
  alias Core.Validators.ServiceReference
  alias Core.Validators.ServiceRequestReference
  alias Core.Validators.VisitContext
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:value, IdentifierValue)
    embeds_one(:type, CodeableConcept, on_replace: :update)
  end

  @fields_required ~w(value)a
  @fields_optional ~w()a

  def changeset(%__MODULE__{} = identifier, params) do
    identifier
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:type, required: true)
  end

  def legal_entity_changeset(%__MODULE__{} = reference, params, client_id) do
    reference
    |> changeset(params)
    |> validate_change(:value, fn :value, value ->
      with true <- value == client_id,
           :ok <-
             LegalEntity.validate(client_id,
               status: "ACTIVE",
               messages: [
                 status: "LegalEntity is not active"
               ]
             ) do
        []
      else
        false -> [value: "Managing_organization does not correspond to user's legal_entity"]
        {:error, message} -> [value: message]
      end
    end)
  end

  def employee_changeset(%__MODULE__{} = reference, params, options \\ []) do
    reference
    |> changeset(params)
    |> validate_change(:value, fn :value, value ->
      with :ok <- Employee.validate(value, options) do
        []
      else
        {:error, message} -> [value: message]
      end
    end)
  end

  def service_changeset(%__MODULE__{} = identifier, params, observations) do
    identifier
    |> changeset(params)
    |> validate_change(:value, fn :value, value ->
      with :ok <- ServiceReference.validate(value, observations: observations) do
        []
      else
        {:error, message} -> [value: message]
      end
    end)
  end

  def diagnostic_report_changeset(%__MODULE__{} = identifier, params, options) do
    identifier
    |> changeset(params)
    |> validate_change(:value, fn :value, value ->
      with :ok <- DiagnosticReportContext.validate(value, options) do
        []
      else
        {:error, message} -> [value: message]
      end
    end)
  end

  def service_request_changeset(%__MODULE__{} = identifier, params, options) do
    identifier
    |> changeset(params)
    |> validate_change(:value, fn :value, value ->
      with :ok <- ServiceRequestReference.validate(value, options) do
        []
      else
        {:error, message} -> [value: message]
      end
    end)
  end

  def observation_changeset(%__MODULE__{} = identifier, params, options) do
    identifier
    |> changeset(params)
    |> validate_change(:value, fn :value, value ->
      with :ok <- ObservationContext.validate(value, options) do
        []
      else
        {:error, message} -> [value: message]
      end
    end)
  end

  def episode_changeset(%__MODULE__{} = identifier, params, options) do
    identifier
    |> changeset(params)
    |> validate_change(:value, fn :value, value ->
      with :ok <- EpisodeReference.validate(value, options) do
        []
      else
        {:error, message} -> [value: message]
      end
    end)
  end

  def visit_changeset(%__MODULE__{} = identifier, params, options) do
    identifier
    |> changeset(params)
    |> validate_change(:value, fn :value, value ->
      with :ok <- VisitContext.validate(value, options) do
        []
      else
        {:error, message} -> [value: message]
      end
    end)
  end

  def division_changeset(%__MODULE__{} = identifier, params, options) do
    identifier
    |> changeset(params)
    |> validate_change(:value, fn :value, value ->
      with :ok <- Division.validate(value, options) do
        []
      else
        {:error, message} -> [value: message]
      end
    end)
  end

  def diagnosis_condition_changeset(%__MODULE__{} = identifier, params, options) do
    identifier
    |> changeset(params)
    |> validate_change(:value, fn :value, value ->
      with :ok <- DiagnosisCondition.validate(value, options) do
        []
      else
        {:error, message} -> [value: message]
      end
    end)
  end

  def supporting_info_changeset(%__MODULE__{} = identifier, params, options) do
    changes = changeset(identifier, params)
    code = changes |> get_change(:type) |> get_change(:coding) |> hd() |> get_change(:code)

    case code do
      "observation" ->
        validate_change(changes, :value, fn :value, value ->
          with :ok <- ObservationReference.validate(value, options) do
            []
          else
            {:error, message} -> [value: message]
          end
        end)

      "diagnostic_report" ->
        validate_change(changes, :value, fn :value, value ->
          with :ok <- DiagnosticReportReference.validate(value, options) do
            []
          else
            {:error, message} -> [value: message]
          end
        end)

      "episode_of_care" ->
        validate_change(changes, :value, fn :value, value ->
          with :ok <- EpisodeReference.validate(value, options) do
            []
          else
            {:error, message} -> [value: message]
          end
        end)
    end
  end

  def reason_reference_changeset(%__MODULE__{} = identifier, params, options) do
    changes = changeset(identifier, params)
    code = changes |> get_change(:type) |> get_change(:coding) |> hd() |> get_change(:code)

    case code do
      "observation" ->
        validate_change(changes, :value, fn :value, value ->
          with :ok <- ObservationContext.validate(value, options) do
            []
          else
            {:error, message} -> [value: message]
          end
        end)

      "condition" ->
        validate_change(changes, :value, fn :value, value ->
          with :ok <- ConditionContext.validate(value, options) do
            []
          else
            {:error, message} -> [value: message]
          end
        end)

      "diagnostic_report" ->
        validate_change(changes, :value, fn :value, value ->
          with :ok <- DiagnosticReportContext.validate(value, options) do
            []
          else
            {:error, message} -> [value: message]
          end
        end)
    end
  end

  def granted_resource_changeset(%__MODULE__{} = identifier, params, options) do
    changes = changeset(identifier, params)
    code = changes |> get_change(:type) |> get_change(:coding) |> hd() |> get_change(:code)

    case code do
      "episode_of_care" ->
        validate_change(changes, :value, fn :value, value ->
          with :ok <- EpisodeReference.validate(value, options) do
            []
          else
            {:error, message} -> [value: message]
          end
        end)

      "diagnostic_report" ->
        validate_change(changes, :value, fn :value, value ->
          with :ok <- DiagnosticReportContext.validate(value, options) do
            []
          else
            {:error, message} -> [value: message]
          end
        end)
    end
  end

  def completed_with_changeset(%__MODULE__{} = identifier, params, options) do
    changes = changeset(identifier, params)
    code = changes |> get_change(:type) |> get_change(:coding) |> hd() |> get_change(:code)

    case code do
      "encounter" ->
        validate_change(changes, :value, fn :value, value ->
          with :ok <- EncounterReference.validate(value, options) do
            []
          else
            {:error, message} -> [value: message]
          end
        end)

      "diagnostic_report" ->
        validate_change(changes, :value, fn :value, value ->
          with :ok <- DiagnosticReportReference.validate(value, options) do
            []
          else
            {:error, message} -> [value: message]
          end
        end)
    end
  end

  def medication_request_changeset(%__MODULE__{} = identifier, params, options) do
    identifier
    |> changeset(params)
    |> validate_change(:value, fn :value, value ->
      with :ok <- MedicationRequestReference.validate(value, options) do
        []
      else
        {:error, message} -> [value: message]
      end
    end)
  end

  def encounter_changeset(%__MODULE__{} = identifier, params, options) do
    identifier
    |> changeset(params)
    |> validate_change(:value, fn :value, value ->
      with :ok <- EncounterReference.validate(value, options) do
        []
      else
        {:error, message} -> [value: message]
      end
    end)
  end

  def drfo_changeset(%__MODULE__{} = identifier, params, options) do
    identifier
    |> changeset(params)
    |> validate_change(:value, fn :value, value ->
      with :ok <- Drfo.validate(value, options) do
        []
      else
        {:error, message} -> [value: message]
      end
    end)
  end

  def code_changeset(%__MODULE__{} = identifier, params, options) do
    changes = changeset(identifier, params)
    code = changes |> get_change(:type) |> get_change(:coding) |> hd() |> get_change(:code)

    case code do
      "service" ->
        validate_change(changes, :value, fn :value, value ->
          with :ok <- ServiceReference.validate(value, options) do
            []
          else
            {:error, message} -> [value: message]
          end
        end)

      "service_group" ->
        validate_change(changes, :value, fn :value, value ->
          with :ok <- ServiceGroupReference.validate(value, options) do
            []
          else
            {:error, message} -> [value: message]
          end
        end)
    end
  end

  def equals_changeset(%__MODULE__{} = identifier, params, options) do
    identifier
    |> changeset(params)
    |> validate_change(:value, fn :value, v ->
      if v == options[:value] do
        []
      else
        [value: Keyword.get(options, :message, "Invalid reference")]
      end
    end)
  end
end
