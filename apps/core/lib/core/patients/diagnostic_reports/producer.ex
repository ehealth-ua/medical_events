defmodule Core.Patients.DiagnosticReports.Producer do
  @moduledoc false

  alias Core.Jobs
  alias Core.Jobs.DiagnosticReportPackageCancelJob
  alias Core.Jobs.DiagnosticReportPackageCreateJob
  alias Core.Patients
  alias Core.Patients.Validators
  alias Core.Validators.JsonSchema

  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  def produce_create_package(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <-
           JsonSchema.validate(
             :diagnostic_report_package_create,
             Map.take(params, ["signed_data"])
           ),
         {:ok, job, diagnostic_report_package_create_job} <-
           Jobs.create(
             user_id,
             DiagnosticReportPackageCreateJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(diagnostic_report_package_create_job) do
      {:ok, job}
    end
  end

  def produce_cancel_package(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <-
           JsonSchema.validate(
             :diagnostic_report_package_cancel,
             Map.take(params, ["signed_data"])
           ),
         {:ok, job, diagnostic_report_package_cancel_job} <-
           Jobs.create(
             user_id,
             DiagnosticReportPackageCancelJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(diagnostic_report_package_cancel_job) do
      {:ok, job}
    end
  end
end
