defmodule Core.Patients.DiagnosticReports.Package do
  @moduledoc false

  alias Core.Job
  alias Core.Jobs
  alias Core.Mongo
  alias Core.Mongo.Transaction
  alias Core.Observation
  alias Core.Observations
  alias Core.Patients.DiagnosticReports
  require Logger

  @collection "patients"
  @observations_collection Observation.metadata().collection

  def save(job, data) do
    %{
      "diagnostic_report" => diagnostic_report,
      "observations" => observations
    } = data

    patient_id = job.patient_id
    patient_id_hash = job.patient_id_hash

    now = DateTime.utc_now()

    set = %{"updated_by" => job.user_id, "updated_at" => now}

    diagnostic_report =
      diagnostic_report
      |> DiagnosticReports.fill_up_diagnostic_report_performer()
      |> DiagnosticReports.fill_up_diagnostic_report_recorded_by()
      |> DiagnosticReports.fill_up_diagnostic_report_results_interpreter()
      |> DiagnosticReports.fill_up_diagnostic_report_managing_organization()
      |> DiagnosticReports.fill_up_diagnostic_report_origin_episode(patient_id_hash)

    set =
      set
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
      |> Mongo.convert_to_uuid("diagnostic_reports.#{diagnostic_report.id}.results_interpreter.value.identifier.value")
      |> Mongo.convert_to_uuid("diagnostic_reports.#{diagnostic_report.id}.managing_organization.identifier.value")
      |> Mongo.convert_to_uuid("diagnostic_reports.#{diagnostic_report.id}.recorded_by.identifier.value")

    links = [
      %{
        "entity" => "diagnostic_report",
        "href" => "/api/patients/#{patient_id}/diagnostic_reports/#{diagnostic_report.id}"
      }
    ]

    observations = Enum.map(observations, &Observations.create/1)

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
      "$set" => set
    })
    |> insert_observations(observations)
    |> Jobs.update(job._id, Job.status(:processed), %{"links" => links}, 200)
    |> Transaction.flush()
  end

  def insert_observations(transaction, observations) do
    Enum.reduce(observations || [], transaction, fn observation, acc ->
      Transaction.add_operation(acc, @observations_collection, :insert, Mongo.prepare_doc(observation))
    end)
  end
end
