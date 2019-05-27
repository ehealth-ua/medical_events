defmodule Core.Patients.Package do
  @moduledoc false

  use Ecto.Schema

  alias Core.AllergyIntolerance
  alias Core.Condition
  alias Core.Device
  alias Core.DiagnosticReport
  alias Core.Encounter
  alias Core.Immunization
  alias Core.Job
  alias Core.Jobs
  alias Core.MedicationStatement
  alias Core.Mongo
  alias Core.Mongo.Transaction
  alias Core.Observation
  alias Core.RiskAssessment
  alias Core.Validators.UniqueIds
  import Ecto.Changeset
  require Logger

  @collection "patients"
  @observations_collection Observation.collection()
  @conditions_collection Condition.collection()

  @primary_key false
  embedded_schema do
    embeds_one(:encounter, Encounter)
    embeds_many(:diagnostic_reports, DiagnosticReport)
    embeds_many(:observations, Observation)
    embeds_many(:conditions, Condition)
    embeds_many(:immunizations, Immunization)
    embeds_many(:allergy_intolerances, AllergyIntolerance)
    embeds_many(:risk_assessments, RiskAssessment)
    embeds_many(:devices, Device)
    embeds_many(:medication_statements, MedicationStatement)

    timestamps(type: :utc_datetime_usec)
  end

  def encounter_changeset(%__MODULE__{} = package, params, patient_id_hash, client_id, visit, conditions) do
    package
    |> cast(params, [])
    |> cast_embed(:encounter,
      with: &Encounter.encounter_package_changeset(&1, &2, patient_id_hash, client_id, visit, conditions)
    )
  end

  def diagnostic_reports_changeset(%__MODULE__{} = package, params, client_id, encounter_id, observations) do
    package
    |> cast(params, [])
    |> cast_embed(:diagnostic_reports,
      with: &DiagnosticReport.encounter_package_changeset(&1, &2, client_id, encounter_id, observations)
    )
    |> validate_change(:diagnostic_reports, &UniqueIds.validate/2)
  end

  def observations_changeset(
        %__MODULE__{} = package,
        params,
        patient_id_hash,
        diagnostic_reports,
        encounter_id,
        client_id
      ) do
    package
    |> cast(params, [])
    |> cast_embed(:observations,
      with:
        &Observation.encounter_package_changeset(&1, &2, patient_id_hash, diagnostic_reports, encounter_id, client_id)
    )
    |> validate_change(:observations, &UniqueIds.validate/2)
  end

  def conditions_changeset(
        %__MODULE__{} = package,
        params,
        patient_id_hash,
        observations,
        encounter_id,
        client_id
      ) do
    package
    |> cast(params, [])
    |> cast_embed(:conditions,
      with: &Condition.encounter_package_changeset(&1, &2, patient_id_hash, observations, encounter_id, client_id)
    )
    |> validate_change(:conditions, &UniqueIds.validate/2)
  end

  def immunizations_changeset(
        %__MODULE__{} = package,
        params,
        patient_id_hash,
        observations,
        encounter_id,
        client_id
      ) do
    package
    |> cast(params, [])
    |> cast_embed(:immunizations,
      with: &Immunization.encounter_package_changeset(&1, &2, patient_id_hash, observations, encounter_id, client_id)
    )
    |> validate_change(:immunizations, &UniqueIds.validate/2)
  end

  def allergy_intolerances_changeset(%__MODULE__{} = package, params, encounter_id, client_id) do
    package
    |> cast(params, [])
    |> cast_embed(:allergy_intolerances,
      with: &AllergyIntolerance.encounter_package_changeset(&1, &2, encounter_id, client_id)
    )
    |> validate_change(:allergy_intolerances, &UniqueIds.validate/2)
  end

  def risk_assessments_changeset(
        %__MODULE__{} = package,
        params,
        patient_id_hash,
        observations,
        conditions,
        diagnostic_reports,
        encounter_id,
        client_id
      ) do
    package
    |> cast(params, [])
    |> cast_embed(:risk_assessments,
      with:
        &RiskAssessment.encounter_package_changeset(
          &1,
          &2,
          patient_id_hash,
          observations,
          conditions,
          diagnostic_reports,
          encounter_id,
          client_id
        )
    )
    |> validate_change(:risk_assessments, &UniqueIds.validate/2)
  end

  def devices_changeset(%__MODULE__{} = package, params, encounter_id, client_id) do
    package
    |> cast(params, [])
    |> cast_embed(:devices,
      with: &Device.encounter_package_changeset(&1, &2, encounter_id, client_id)
    )
    |> validate_change(:devices, &UniqueIds.validate/2)
  end

  def medication_statements_changeset(%__MODULE__{} = package, params, patient_id_hash, encounter_id, client_id) do
    package
    |> cast(params, [])
    |> cast_embed(:medication_statements,
      with: &MedicationStatement.encounter_package_changeset(&1, &2, patient_id_hash, encounter_id, client_id)
    )
    |> validate_change(:medication_statements, &UniqueIds.validate/2)
  end

  def save(job, data) do
    %{
      "visit" => visit,
      "encounter" => encounter,
      "immunizations" => immunizations,
      "immunization_updates" => immunization_updates,
      "allergy_intolerances" => allergy_intolerances,
      "risk_assessments" => risk_assessments,
      "devices" => devices,
      "medication_statements" => medication_statements,
      "diagnostic_reports" => diagnostic_reports,
      "diagnoses_history" => diagnoses_history,
      "observations" => observations,
      "conditions" => conditions
    } = data

    patient_id = job.patient_id
    patient_id_hash = job.patient_id_hash

    now = DateTime.utc_now()

    set =
      %{"updated_by" => job.user_id, "updated_at" => now}
      |> Mongo.add_to_set(encounter, "encounters.#{encounter.id}")
      |> add_visit_to_set(visit)

    set =
      Mongo.add_to_set(
        set,
        diagnoses_history.diagnoses,
        "episodes.#{encounter.episode.identifier.value}.current_diagnoses"
      )

    push =
      Mongo.add_to_push(
        %{},
        diagnoses_history,
        "episodes.#{encounter.episode.identifier.value}.diagnoses_history"
      )

    set = Enum.reduce(immunizations, set, &add_immunization_to_set/2)
    set = Enum.reduce(immunization_updates, set, &add_db_immunization_to_set/2)
    push = Enum.reduce(immunization_updates, push, &add_db_immunization_to_push/2)

    set =
      Enum.reduce(allergy_intolerances, set, fn allergy_intolerance, acc ->
        allergy_intolerance = AllergyIntolerance.fill_up_asserter(allergy_intolerance)
        Mongo.add_to_set(acc, allergy_intolerance, "allergy_intolerances.#{allergy_intolerance.id}")
      end)

    set =
      Enum.reduce(risk_assessments, set, fn risk_assessment, acc ->
        risk_assessment = RiskAssessment.fill_up_performer(risk_assessment)
        Mongo.add_to_set(acc, risk_assessment, "risk_assessments.#{risk_assessment.id}")
      end)

    set =
      Enum.reduce(devices, set, fn device, acc ->
        device = Device.fill_up_asserter(device)
        Mongo.add_to_set(acc, device, "devices.#{device.id}")
      end)

    set =
      Enum.reduce(medication_statements, set, fn medication_statement, acc ->
        medication_statement = MedicationStatement.fill_up_asserter(medication_statement)
        Mongo.add_to_set(acc, medication_statement, "medication_statements.#{medication_statement.id}")
      end)

    set =
      Enum.reduce(diagnostic_reports, set, fn diagnostic_report, acc ->
        diagnostic_report =
          diagnostic_report
          |> DiagnosticReport.fill_up_performer()
          |> DiagnosticReport.fill_up_recorded_by()
          |> DiagnosticReport.fill_up_results_interpreter()
          |> DiagnosticReport.fill_up_managing_organization()
          |> DiagnosticReport.fill_up_origin_episode(patient_id_hash)

        Mongo.add_to_set(acc, diagnostic_report, "diagnostic_reports.#{diagnostic_report.id}")
      end)

    links = [
      %{
        "entity" => "encounter",
        "href" => "/api/patients/#{patient_id}/encounters/#{encounter.id}"
      }
    ]

    links =
      Enum.reduce(immunizations, links, fn immunization, acc ->
        acc ++
          [
            %{
              "entity" => "immunization",
              "href" => "/api/patients/#{patient_id}/immunizations/#{immunization.id}"
            }
          ]
      end)

    links =
      Enum.reduce(immunization_updates, links, fn immunization, acc ->
        acc ++
          [
            %{
              "entity" => "immunization",
              "href" => "/api/patients/#{patient_id}/immunizations/#{immunization.id}"
            }
          ]
      end)

    links =
      Enum.reduce(allergy_intolerances, links, fn allergy_intolerance, acc ->
        acc ++
          [
            %{
              "entity" => "allergy_intolerance",
              "href" => "/api/patients/#{patient_id}/allergy_intolerances/#{allergy_intolerance.id}"
            }
          ]
      end)

    links =
      Enum.reduce(risk_assessments, links, fn risk_assessment, acc ->
        acc ++
          [
            %{
              "entity" => "risk_assessment",
              "href" => "/api/patients/#{patient_id}/risk_assessments/#{risk_assessment.id}"
            }
          ]
      end)

    links =
      Enum.reduce(devices, links, fn device, acc ->
        acc ++
          [
            %{
              "entity" => "device",
              "href" => "/api/patients/#{patient_id}/devices/#{device.id}"
            }
          ]
      end)

    links =
      Enum.reduce(medication_statements, links, fn medication_statement, acc ->
        acc ++
          [
            %{
              "entity" => "medication_statement",
              "href" => "/api/patients/#{patient_id}/medication_statements/#{medication_statement.id}"
            }
          ]
      end)

    links =
      Enum.reduce(diagnostic_reports, links, fn diagnostic_report, acc ->
        acc ++
          [
            %{
              "entity" => "diagnostic_report",
              "href" => "/api/patients/#{patient_id}/diagnostic_reports/#{diagnostic_report.id}"
            }
          ]
      end)

    links =
      Enum.reduce(conditions, links, fn condition, acc ->
        acc ++
          [
            %{
              "entity" => "condition",
              "href" => "/api/patients/#{patient_id}/conditions/#{condition._id}"
            }
          ]
      end)

    links =
      Enum.reduce(observations, links, fn observation, acc ->
        acc ++
          [
            %{
              "entity" => "observation",
              "href" => "/api/patients/#{patient_id}/observations/#{observation._id}"
            }
          ]
      end)

    %Transaction{actor_id: job.user_id}
    |> Transaction.add_operation(
      @collection,
      :update,
      %{"_id" => patient_id_hash},
      %{
        "$set" => set,
        "$push" => push
      },
      patient_id_hash
    )
    |> insert_conditions(conditions)
    |> insert_observations(observations)
    |> Jobs.update(job._id, Job.status(:processed), %{"links" => links}, 200)
    |> Transaction.flush()
  end

  def insert_conditions(transaction, conditions) do
    Enum.reduce(conditions || [], transaction, fn condition, acc ->
      Transaction.add_operation(acc, @conditions_collection, :insert, condition, condition._id)
    end)
  end

  def insert_observations(transaction, observations) do
    Enum.reduce(observations || [], transaction, fn observation, acc ->
      Transaction.add_operation(acc, @observations_collection, :insert, observation, observation._id)
    end)
  end

  defp add_immunization_to_set(%{id: %BSON.Binary{}} = immunization, set) do
    Mongo.add_to_set(set, immunization, "immunizations.#{immunization.id}")
  end

  defp add_immunization_to_set(immunization, set) do
    immunization = Immunization.fill_up_performer(immunization)
    Mongo.add_to_set(set, immunization, "immunizations.#{immunization.id}")
  end

  defp add_db_immunization_to_set(%{id: %BSON.Binary{} = id} = immunization, set) do
    set
    |> Mongo.add_to_set(immunization.updated_by, "immunizations.#{id}.updated_by")
    |> Mongo.add_to_set(immunization.updated_at, "immunizations.#{id}.updated_at")
  end

  defp add_db_immunization_to_push(%{id: %BSON.Binary{} = id} = immunization, push) do
    Mongo.add_to_push(push, immunization.reactions, "immunizations.#{id}.reactions")
  end

  defp add_visit_to_set(set, nil), do: set

  defp add_visit_to_set(set, visit) do
    Mongo.add_to_set(set, visit, "visits.#{visit.id}")
  end
end
