defmodule Core.Patients.DiagnosticReports.Package do
  @moduledoc false

  alias Core.DiagnosticReport
  alias Core.Job
  alias Core.Jobs
  alias Core.Mongo
  alias Core.Mongo.Transaction
  alias Core.Observation
  alias Core.Validators.UniqueIds
  use Ecto.Schema
  import Ecto.Changeset
  require Logger

  @collection "patients"
  @observations_collection Observation.collection()

  @primary_key false
  embedded_schema do
    embeds_one(:diagnostic_report, DiagnosticReport)
    embeds_many(:observations, Observation)
  end

  def diagnostic_report_changeset(%__MODULE__{} = package, params, client_id, observations) do
    package
    |> cast(params, [])
    |> cast_embed(:diagnostic_report,
      with: &DiagnosticReport.diagnostic_report_package_changeset(&1, &2, client_id, observations)
    )
  end

  def observations_changeset(
        %__MODULE__{} = package,
        params,
        diagnostic_report_id,
        client_id
      ) do
    package
    |> cast(params, [])
    |> cast_embed(:observations,
      with: &Observation.diagnostic_report_package_changeset(&1, &2, diagnostic_report_id, client_id)
    )
    |> validate_change(:observations, &UniqueIds.validate/2)
  end

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
      |> DiagnosticReport.fill_up_performer()
      |> DiagnosticReport.fill_up_recorded_by()
      |> DiagnosticReport.fill_up_results_interpreter()
      |> DiagnosticReport.fill_up_managing_organization()
      |> DiagnosticReport.fill_up_origin_episode(patient_id_hash)

    set = Mongo.add_to_set(set, diagnostic_report, "diagnostic_reports.#{diagnostic_report.id}")

    links = [
      %{
        "entity" => "diagnostic_report",
        "href" => "/api/patients/#{patient_id}/diagnostic_reports/#{diagnostic_report.id}"
      }
    ]

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

    %Transaction{actor_id: job.user_id, patient_id: patient_id_hash}
    |> Transaction.add_operation(
      @collection,
      :update,
      %{"_id" => patient_id_hash},
      %{
        "$set" => set
      },
      patient_id_hash
    )
    |> insert_observations(observations)
    |> Jobs.update(job._id, Job.status(:processed), %{"links" => links}, 200)
    |> Jobs.complete(job)
  end

  def insert_observations(transaction, observations) do
    Enum.reduce(observations || [], transaction, fn observation, acc ->
      observation = Observation.fill_up_performer(observation)
      Transaction.add_operation(acc, @observations_collection, :insert, observation, observation._id)
    end)
  end
end
