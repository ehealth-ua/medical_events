defmodule Core.Approvals.Producer do
  @moduledoc false

  alias Core.Approval
  alias Core.Approvals
  alias Core.Jobs
  alias Core.Jobs.ApprovalCreateJob
  alias Core.Jobs.ApprovalResendJob
  alias Core.Patients
  alias Core.Validators.JsonSchema
  alias Core.Validators.OneOf
  alias Core.Validators.Patient, as: PatientValidator

  @create_request_params ~w(
    resources
    service_request
    granted_to
    access_level
  )

  @one_of_create_request_params %{
    "$" => %{"params" => ["resources", "service_request"], "required" => true}
  }

  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  def produce_create_approval(
        %{"patient_id_hash" => patient_id_hash} = params,
        user_id,
        client_id
      ) do
    with %{"status" => patient_status} <- Patients.get_by_id(patient_id_hash, projection: [status: true]),
         :ok <- PatientValidator.is_active(patient_status),
         :ok <- JsonSchema.validate(:approval_create, Map.take(params, @create_request_params)),
         :ok <-
           OneOf.validate(Map.take(params, @create_request_params), @one_of_create_request_params, render_error: false),
         {:ok, job, approval_create_job} <-
           Jobs.create(
             user_id,
             patient_id_hash,
             ApprovalCreateJob,
             Map.merge(params, %{
               "user_id" => user_id,
               "client_id" => client_id,
               "salt" => DateTime.utc_now()
             })
           ),
         :ok <- @kafka_producer.publish_medical_event(approval_create_job) do
      {:ok, job}
    end
  end

  def produce_resend_approval(
        %{"patient_id_hash" => patient_id_hash, "id" => id} = params,
        user_id,
        client_id
      ) do
    with %{"status" => patient_status} <- Patients.get_by_id(patient_id_hash, projection: [status: true]),
         :ok <- PatientValidator.is_active(patient_status),
         {:ok, %Approval{}} <- Approvals.get_by_id(id, projection: [_id: true]),
         {:ok, job, approval_resend_job} <-
           Jobs.create(
             user_id,
             patient_id_hash,
             ApprovalResendJob,
             Map.merge(params, %{"user_id" => user_id, "client_id" => client_id})
           ),
         :ok <- @kafka_producer.publish_medical_event(approval_resend_job) do
      {:ok, job}
    end
  end
end
