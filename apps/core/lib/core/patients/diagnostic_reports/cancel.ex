defmodule Core.Patients.DiagnosticReports.Cancel do
  @moduledoc false

  alias Core.DateView
  alias Core.DiagnosticReport
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.DiagnosticReportPackageCancelJob
  alias Core.Mongo
  alias Core.Mongo.Transaction
  alias Core.Observation
  alias Core.Observations
  alias Core.Patient
  alias Core.ReferenceView
  alias Core.UUIDView

  require Logger

  @media_storage Application.get_env(:core, :microservices)[:media_storage]

  @patients_collection Patient.collection()
  @observations_collection Observation.collection()

  @entered_in_error "entered_in_error"

  @doc """
  Performs validation by comparing diagnostic report packages which created retrieved from job signed data and database
  Package entities except `diagnostic_report` are MapSet's to ignore position in list
  """
  def validate(decoded_content, %DiagnosticReport{} = diagnostic_report, patient_id_hash) do
    diagnostic_report_request_package = create_diagnostic_report_package_from_request(decoded_content)

    with :ok <- validate_has_entity_entered_in_error(decoded_content),
         {:ok, diagnostic_report_package} <-
           create_diagnostic_report_package(diagnostic_report, patient_id_hash, decoded_content),
         :ok <- validate_diagnostic_report_packages(diagnostic_report_package, diagnostic_report_request_package) do
      :ok
    end
  end

  def save(
        package_data,
        diagnostic_report_id,
        %DiagnosticReportPackageCancelJob{patient_id: patient_id, user_id: user_id} = job
      ) do
    observations_ids = get_observations_ids(package_data)

    with :ok <- save_signed_content(patient_id, diagnostic_report_id, job.signed_data),
         set <- update_patient(user_id, package_data) do
      %Transaction{actor_id: user_id, patient_id: job.patient_id_hash}
      |> Transaction.add_operation(
        @patients_collection,
        :update,
        %{"_id" => job.patient_id_hash},
        %{"$set" => set},
        job.patient_id_hash
      )
      |> update_observations(observations_ids, user_id)
      |> Jobs.update(job._id, Job.status(:processed), %{}, 200)
      |> Jobs.complete(job)
    end
  end

  defp update_observations(%Transaction{} = transaction, ids, user_id) do
    Enum.reduce(ids, transaction, fn id, acc ->
      Transaction.add_operation(
        acc,
        @observations_collection,
        :update,
        %{"_id" => Mongo.string_to_uuid(id)},
        %{
          "$set" => %{
            "status" => @entered_in_error,
            "updated_by" => Mongo.string_to_uuid(user_id),
            "updated_at" => DateTime.utc_now()
          }
        },
        Mongo.string_to_uuid(id)
      )
    end)
  end

  defp save_signed_content(patient_id, diagnostic_report_id, signed_data) do
    resource_name = "#{diagnostic_report_id}/cancel"
    files = [{'signed_content.txt', signed_data}]
    {:ok, {_, compressed_content}} = :zip.create("signed_content.zip", files, [:memory])

    @media_storage.save(
      patient_id,
      compressed_content,
      Confex.fetch_env!(:core, Core.Microservices.MediaStorage)[:diagnostic_report_bucket],
      resource_name
    )
  end

  defp get_observations_ids(package_data) do
    package_data
    |> Map.get("observations", [])
    |> Enum.filter(&(Map.get(&1, "status") == @entered_in_error))
    |> Enum.map(&Map.get(&1, "id"))
  end

  defp update_patient(user_id, %{"diagnostic_report" => diagnostic_report}) do
    now = DateTime.utc_now()

    %{"updated_by" => user_id, "updated_at" => now}
    |> set_diagnostic_report(user_id, diagnostic_report, now)
    |> Mongo.prepare_doc()
  end

  defp set_diagnostic_report(set, user_id, %{"id" => diagnostic_report_id} = diagnostic_report, now) do
    set
    |> Mongo.add_to_set(user_id, "diagnostic_reports.#{diagnostic_report_id}.updated_by")
    |> Mongo.add_to_set(now, "diagnostic_reports.#{diagnostic_report_id}.updated_at")
    |> Mongo.add_to_set(
      diagnostic_report["cancellation_reason"],
      "diagnostic_reports.#{diagnostic_report_id}.cancellation_reason"
    )
    |> Mongo.add_to_set(
      diagnostic_report["explanatory_letter"],
      "diagnostic_reports.#{diagnostic_report_id}.explanatory_letter"
    )
    |> set_diagnostic_report_status(diagnostic_report)
  end

  defp set_diagnostic_report_status(set, %{"id" => id, "status" => @entered_in_error}) do
    Mongo.add_to_set(set, @entered_in_error, "diagnostic_reports.#{id}.status")
  end

  defp set_diagnostic_report_status(set, _), do: set

  defp create_diagnostic_report_package(
         %DiagnosticReport{id: diagnostic_report_id} = diagnostic_report,
         patient_id_hash,
         decoded_content
       ) do
    package = %{
      diagnostic_report: diagnostic_report
    }

    package =
      if decoded_content["observations"] do
        ids = Enum.map(decoded_content["observations"], & &1["id"])
        observations = get_observations(ids, patient_id_hash, diagnostic_report_id)
        Map.put(package, :observations, observations)
      else
        package
      end

    with :ok <- validate_package_has_no_entered_in_error_entities(package) do
      {:ok, render_package_entities(package)}
    end
  end

  defp validate_has_entity_entered_in_error(%{"diagnostic_report" => diagnostic_report} = decoded_content) do
    [
      [diagnostic_report["status"]],
      get_observations_statuses(decoded_content["observations"], "status")
    ]
    |> Enum.flat_map(& &1)
    |> Enum.any?(&(&1 == @entered_in_error))
    |> case do
      true -> :ok
      _ -> {:ok, %{"error" => ~s(At least one entity should have status "entered_in_error")}, 409}
    end
  end

  defp get_observations_statuses(nil, _), do: []
  defp get_observations_statuses(entities, status_field), do: Enum.map(entities, &Map.get(&1, status_field))

  defp validate_package_has_no_entered_in_error_entities(%{diagnostic_report: diagnostic_report} = package) do
    [
      diagnostic_report: [diagnostic_report.status],
      observation: get_observations_statuses(package[:observations], :status)
    ]
    |> Enum.reject(fn {_, statuses} -> statuses == [] end)
    |> Enum.reduce_while(:ok, fn {key, statuses}, _acc ->
      case @entered_in_error in statuses do
        true -> {:halt, {:ok, %{"error" => "Invalid transition for #{key} - already entered_in_error"}, 409}}
        _ -> {:cont, :ok}
      end
    end)
  end

  defp render_package_entities(package) do
    rendered_package = %{
      diagnostic_report: render(:diagnostic_report, package.diagnostic_report)
    }

    if package[:observations] do
      Map.put(rendered_package, :observations, render(:observations, package.observations))
    else
      rendered_package
    end
  end

  defp create_diagnostic_report_package_from_request(decoded_content) do
    diagnostic_report =
      decoded_content
      |> Map.get("diagnostic_report")
      |> DiagnosticReport.create()

    package = %{
      diagnostic_report: diagnostic_report
    }

    if decoded_content["observations"] do
      observations =
        decoded_content
        |> Map.get("observations", [])
        |> Enum.map(&Observation.create/1)

      package
      |> Map.put(:observations, observations)
      |> render_package_entities()
    else
      render_package_entities(package)
    end
  end

  defp validate_diagnostic_report_packages(package, request_package) do
    package = Iteraptor.to_flatmap(package)
    request_package = Iteraptor.to_flatmap(request_package)

    request_package
    |> Enum.reject(fn {key, value} -> package[key] == value end)
    |> case do
      [] ->
        :ok

      [{error_path, _} | _] ->
        {:ok,
         %{
           "error" => "Submitted signed content does not correspond to previously created content: #{error_path}"
         }, 409}
    end
  end

  defp get_observations(ids, patient_id_hash, diagnostic_report_id) do
    patient_id_hash
    |> Observations.get_by_diagnostic_report_id(diagnostic_report_id)
    |> Enum.filter(&(UUID.binary_to_string!(&1._id.binary) in ids))
  end

  defp render(:observations, observations) do
    Enum.map(observations, fn observation ->
      observation
      |> Map.take(~w(primary_source comment)a)
      |> Map.merge(%{
        id: UUIDView.render(observation._id),
        issued: DateView.render_datetime(observation.issued),
        based_on: ReferenceView.render(observation.based_on),
        method: ReferenceView.render(observation.method),
        categories: ReferenceView.render(observation.categories),
        interpretation: ReferenceView.render(observation.interpretation),
        code: ReferenceView.render(observation.code),
        body_site: ReferenceView.render(observation.body_site),
        reference_ranges: ReferenceView.render(observation.reference_ranges),
        components: ReferenceView.render(observation.components)
      })
      |> Map.merge(ReferenceView.render_effective_at(observation.effective_at))
      |> Map.merge(ReferenceView.render_source(observation.source))
      |> Map.merge(ReferenceView.render_value(observation.value))
      |> ReferenceView.remove_display_values()
    end)
  end

  defp render(:diagnostic_report, diagnostic_report) do
    diagnostic_report
    |> Map.take(~w(primary_source conclusion)a)
    |> Map.merge(%{
      id: UUIDView.render(diagnostic_report.id),
      based_on: ReferenceView.render(diagnostic_report.based_on),
      category: ReferenceView.render(diagnostic_report.category),
      code: ReferenceView.render(diagnostic_report.code),
      issued: DateView.render_datetime(diagnostic_report.issued),
      recorded_by: ReferenceView.render(diagnostic_report.recorded_by),
      results_interpreter: ReferenceView.render(diagnostic_report.results_interpreter),
      managing_organization: ReferenceView.render(diagnostic_report.managing_organization),
      conclusion_code: ReferenceView.render(diagnostic_report.conclusion_code)
    })
    |> Map.merge(ReferenceView.render_effective_at(diagnostic_report.effective))
    |> Map.merge(ReferenceView.render_source(diagnostic_report.source))
    |> ReferenceView.remove_display_values()
  end
end
