defmodule Core.Patients.Package do
  @moduledoc false

  alias Core.Condition
  alias Core.Conditions
  alias Core.DiagnosesHistory
  alias Core.Job
  alias Core.Jobs
  alias Core.Mongo
  alias Core.Mongo.Transaction
  alias Core.Observation
  alias Core.Observations
  alias Core.Patients.AllergyIntolerances
  alias Core.Patients.Devices
  alias Core.Patients.DiagnosticReports
  alias Core.Patients.Immunizations
  alias Core.Patients.MedicationStatements
  alias Core.Patients.RiskAssessments
  require Logger

  @collection "patients"
  @observations_collection Observation.metadata().collection
  @conditions_collection Condition.metadata().collection

  def save(job, data) do
    %{
      "visit" => visit,
      "encounter" => encounter,
      "immunizations" => immunizations,
      "allergy_intolerances" => allergy_intolerances,
      "risk_assessments" => risk_assessments,
      "devices" => devices,
      "medication_statements" => medication_statements,
      "diagnostic_reports" => diagnostic_reports,
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
      |> Mongo.convert_to_uuid("encounters.#{encounter.id}.id")
      |> Mongo.convert_to_uuid("encounters.#{encounter.id}.inserted_by")
      |> Mongo.convert_to_uuid("encounters.#{encounter.id}.updated_by")
      |> Mongo.convert_to_uuid("encounters.#{encounter.id}.division.identifier.value")
      |> Mongo.convert_to_uuid("encounters.#{encounter.id}.episode.identifier.value")
      |> Mongo.convert_to_uuid("encounters.#{encounter.id}.performer.identifier.value")
      |> Mongo.convert_to_uuid("encounters.#{encounter.id}.visit.identifier.value")
      |> Mongo.convert_to_uuid(
        "encounters.#{encounter.id}.diagnoses",
        ~w(condition identifier value)a
      )
      |> Mongo.convert_to_uuid(
        "encounters.#{encounter.id}.incoming_referrals",
        ~w(identifier value)a
      )
      |> Mongo.convert_to_uuid(
        "encounters.#{encounter.id}.supporting_info",
        ~w(identifier value)a
      )
      |> Mongo.convert_to_uuid("encounters.#{encounter.id}.service_provider.identifier.value")
      |> Mongo.convert_to_uuid("updated_by")

    diagnoses_history =
      DiagnosesHistory.create(%{
        "date" => now,
        "evidence" => %{
          "identifier" => %{
            "type" => %{
              "coding" => [
                %{
                  "system" => "eHealth/resources",
                  "code" => "encounter"
                }
              ]
            },
            "value" => Mongo.string_to_uuid(encounter.id)
          }
        },
        "is_active" => true
      })

    diagnoses_history = %{
      diagnoses_history
      | diagnoses:
          Enum.map(encounter.diagnoses, fn diagnosis ->
            condition = diagnosis.condition

            %{
              diagnosis
              | condition: %{
                  condition
                  | identifier: %{
                      condition.identifier
                      | value: Mongo.string_to_uuid(condition.identifier.value)
                    }
                }
            }
          end)
    }

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

    set =
      Enum.reduce(allergy_intolerances, set, fn allergy_intolerance, acc ->
        allergy_intolerance = AllergyIntolerances.fill_up_allergy_intolerance_asserter(allergy_intolerance)

        acc
        |> Mongo.add_to_set(
          allergy_intolerance,
          "allergy_intolerances.#{allergy_intolerance.id}"
        )
        |> Mongo.convert_to_uuid("allergy_intolerances.#{allergy_intolerance.id}.id")
        |> Mongo.convert_to_uuid("allergy_intolerances.#{allergy_intolerance.id}.inserted_by")
        |> Mongo.convert_to_uuid("allergy_intolerances.#{allergy_intolerance.id}.updated_by")
        |> Mongo.convert_to_uuid("allergy_intolerances.#{allergy_intolerance.id}.context.identifier.value")
        |> Mongo.convert_to_uuid("allergy_intolerances.#{allergy_intolerance.id}.source.value.identifier.value")
      end)

    set =
      Enum.reduce(risk_assessments, set, fn risk_assessment, acc ->
        risk_assessment = RiskAssessments.fill_up_risk_assessment_performer(risk_assessment)

        acc
        |> Mongo.add_to_set(
          risk_assessment,
          "risk_assessments.#{risk_assessment.id}"
        )
        |> Mongo.convert_to_uuid("risk_assessments.#{risk_assessment.id}.id")
        |> Mongo.convert_to_uuid("risk_assessments.#{risk_assessment.id}.inserted_by")
        |> Mongo.convert_to_uuid("risk_assessments.#{risk_assessment.id}.updated_by")
        |> Mongo.convert_to_uuid("risk_assessments.#{risk_assessment.id}.context.identifier.value")
        |> Mongo.convert_to_uuid("risk_assessments.#{risk_assessment.id}.performer.identifier.value")
        |> Mongo.convert_to_uuid("risk_assessments.#{risk_assessment.id}.basis.value")
        |> Mongo.convert_to_uuid("risk_assessments.#{risk_assessment.id}.reason.reference.identifier.value")
      end)

    set =
      Enum.reduce(devices, set, fn device, acc ->
        device = Devices.fill_up_device_asserter(device)

        acc
        |> Mongo.add_to_set(
          device,
          "devices.#{device.id}"
        )
        |> Mongo.convert_to_uuid("devices.#{device.id}.id")
        |> Mongo.convert_to_uuid("devices.#{device.id}.inserted_by")
        |> Mongo.convert_to_uuid("devices.#{device.id}.updated_by")
        |> Mongo.convert_to_uuid("devices.#{device.id}.context.identifier.value")
        |> Mongo.convert_to_uuid("devices.#{device.id}.source.value.identifier.value")
      end)

    set =
      Enum.reduce(medication_statements, set, fn medication_statement, acc ->
        medication_statement = MedicationStatements.fill_up_medication_statement_asserter(medication_statement)

        acc
        |> Mongo.add_to_set(
          medication_statement,
          "medication_statements.#{medication_statement.id}"
        )
        |> Mongo.convert_to_uuid("medication_statements.#{medication_statement.id}.id")
        |> Mongo.convert_to_uuid("medication_statements.#{medication_statement.id}.inserted_by")
        |> Mongo.convert_to_uuid("medication_statements.#{medication_statement.id}.updated_by")
        |> Mongo.convert_to_uuid("medication_statements.#{medication_statement.id}.context.identifier.value")
        |> Mongo.convert_to_uuid("medication_statements.#{medication_statement.id}.source.value.identifier.value")
        |> Mongo.convert_to_uuid("medication_statements.#{medication_statement.id}.based_on.identifier.value")
      end)

    set =
      Enum.reduce(diagnostic_reports, set, fn diagnostic_report, acc ->
        diagnostic_report =
          diagnostic_report
          |> DiagnosticReports.fill_up_diagnostic_report_performer()
          |> DiagnosticReports.fill_up_diagnostic_report_recorded_by()
          |> DiagnosticReports.fill_up_diagnostic_report_results_interpreter()
          |> DiagnosticReports.fill_up_diagnostic_report_managing_organization()
          |> DiagnosticReports.fill_up_diagnostic_report_origin_episode(patient_id_hash)

        acc
        |> Mongo.add_to_set(
          diagnostic_report,
          "diagnostic_reports.#{diagnostic_report.id}"
        )
        |> Mongo.convert_to_uuid("diagnostic_reports.#{diagnostic_report.id}.id")
        |> Mongo.convert_to_uuid("diagnostic_reports.#{diagnostic_report.id}.inserted_by")
        |> Mongo.convert_to_uuid("diagnostic_reports.#{diagnostic_report.id}.updated_by")
        |> Mongo.convert_to_uuid("diagnostic_reports.#{diagnostic_report.id}.encounter.identifier.value")
        |> Mongo.convert_to_uuid("diagnostic_reports.#{diagnostic_report.id}.source.value.value.identifier.value")
        |> Mongo.convert_to_uuid("diagnostic_reports.#{diagnostic_report.id}.based_on.identifier.value")
        |> Mongo.convert_to_uuid(
          "diagnostic_reports.#{diagnostic_report.id}.results_interpreter.value.identifier.value"
        )
        |> Mongo.convert_to_uuid("diagnostic_reports.#{diagnostic_report.id}.managing_organization.identifier.value")
        |> Mongo.convert_to_uuid("diagnostic_reports.#{diagnostic_report.id}.recorded_by.identifier.value")
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

    conditions = Enum.map(conditions, &Conditions.create/1)
    observations = Enum.map(observations, &Observations.create/1)

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

    %Transaction{}
    |> Transaction.add_operation(@collection, :update, %{"_id" => patient_id_hash}, %{
      "$set" => set,
      "$push" => push
    })
    |> insert_conditions(conditions)
    |> insert_observations(observations)
    |> Jobs.update(job._id, Job.status(:processed), %{"links" => links}, 200)
    |> Transaction.flush()
  end

  def insert_conditions(transaction, conditions) do
    Enum.reduce(conditions || [], transaction, fn condition, acc ->
      Transaction.add_operation(acc, @conditions_collection, :insert, Mongo.prepare_doc(condition))
    end)
  end

  def insert_observations(transaction, observations) do
    Enum.reduce(observations || [], transaction, fn observation, acc ->
      Transaction.add_operation(acc, @observations_collection, :insert, Mongo.prepare_doc(observation))
    end)
  end

  defp add_immunization_to_set(%{id: %BSON.Binary{}} = immunization, set) do
    set
    |> Mongo.add_to_set(immunization, "immunizations.#{immunization.id}")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.updated_by")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.reactions", ~w(detail identifier value)a)
  end

  defp add_immunization_to_set(immunization, set) do
    immunization = Immunizations.fill_up_immunization_performer(immunization)

    set
    |> Mongo.add_to_set(immunization, "immunizations.#{immunization.id}")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.id")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.inserted_by")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.updated_by")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.context.identifier.value")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.legal_entity.identifier.value")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.source.value.identifier.value")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.reactions", ~w(detail identifier value)a)
  end

  defp add_visit_to_set(set, nil), do: set

  defp add_visit_to_set(set, visit) do
    visit_id = visit.id

    set
    |> Mongo.add_to_set(visit, "visits.#{visit_id}")
    |> Mongo.convert_to_uuid("visits.#{visit_id}.id")
    |> Mongo.convert_to_uuid("visits.#{visit_id}.inserted_by")
    |> Mongo.convert_to_uuid("visits.#{visit_id}.updated_by")
  end
end
