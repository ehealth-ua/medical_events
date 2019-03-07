defmodule Core.ServiceRequests.Producer do
  @moduledoc false

  alias Core.Jobs
  alias Core.Jobs.ServiceRequestCancelJob
  alias Core.Jobs.ServiceRequestCompleteJob
  alias Core.Jobs.ServiceRequestCreateJob
  alias Core.Jobs.ServiceRequestProcessJob
  alias Core.Jobs.ServiceRequestRecallJob
  alias Core.Jobs.ServiceRequestReleaseJob
  alias Core.Jobs.ServiceRequestUseJob
  alias Core.Patients
  alias Core.Patients.Encryptor
  alias Core.Patients.Validators
  alias Core.ServiceRequest
  alias Core.ServiceRequests
  alias Core.Validators.JsonSchema

  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  def produce_create_service_request(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:service_request_create, Map.take(params, ~w(signed_data))),
         {:ok, job, service_request_create_job} <-
           Jobs.create(
             ServiceRequestCreateJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(service_request_create_job) do
      {:ok, job}
    end
  end

  def produce_use_service_request(params, user_id, client_id) do
    with :ok <- JsonSchema.validate(:service_request_use, Map.take(params, ~w(used_by_employee used_by_legal_entity))),
         {:ok, %ServiceRequest{subject: patient_id_hash}} <- ServiceRequests.get_by_id(params["service_request_id"]),
         {:ok, job, service_request_use_job} <-
           Jobs.create(
             ServiceRequestUseJob,
             params
             |> Map.put("patient_id", Encryptor.decrypt(patient_id_hash))
             |> Map.put("patient_id_hash", patient_id_hash)
             |> Map.put("user_id", user_id)
             |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(service_request_use_job) do
      {:ok, job}
    end
  end

  def produce_release_service_request(params, user_id, client_id) do
    with {:ok, %ServiceRequest{subject: patient_id_hash}} <- ServiceRequests.get_by_id(params["service_request_id"]),
         {:ok, job, service_request_release_job} <-
           Jobs.create(
             ServiceRequestReleaseJob,
             params
             |> Map.put("patient_id", Encryptor.decrypt(patient_id_hash))
             |> Map.put("patient_id_hash", patient_id_hash)
             |> Map.put("user_id", user_id)
             |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(service_request_release_job) do
      {:ok, job}
    end
  end

  def produce_recall_service_request(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:service_request_recall, Map.take(params, ~w(signed_data))),
         {:ok, %ServiceRequest{}} <- ServiceRequests.get_by_id(params["service_request_id"]),
         {:ok, job, service_request_recall_job} <-
           Jobs.create(
             ServiceRequestRecallJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(service_request_recall_job) do
      {:ok, job}
    end
  end

  def produce_cancel_service_request(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:service_request_cancel, Map.take(params, ~w(signed_data))),
         {:ok, %ServiceRequest{}} <- ServiceRequests.get_by_id(params["service_request_id"]),
         {:ok, job, service_request_cancel_job} <-
           Jobs.create(
             ServiceRequestCancelJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(service_request_cancel_job) do
      {:ok, job}
    end
  end

  def produce_complete_service_request(params, user_id, client_id) do
    with :ok <- JsonSchema.validate(:service_request_complete, Map.take(params, ~w(completed_with status_reason))),
         {:ok, %ServiceRequest{subject: patient_id_hash}} <- ServiceRequests.get_by_id(params["service_request_id"]),
         {:ok, job, service_request_complete_job} <-
           Jobs.create(
             ServiceRequestCompleteJob,
             params
             |> Map.put("patient_id", Encryptor.decrypt(patient_id_hash))
             |> Map.put("patient_id_hash", patient_id_hash)
             |> Map.put("user_id", user_id)
             |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(service_request_complete_job) do
      {:ok, job}
    end
  end

  def produce_process_service_request(params, user_id, client_id) do
    with {:ok, %ServiceRequest{subject: patient_id_hash}} <- ServiceRequests.get_by_id(params["service_request_id"]),
         {:ok, job, service_request_process_job} <-
           Jobs.create(
             ServiceRequestProcessJob,
             params
             |> Map.put("patient_id", Encryptor.decrypt(patient_id_hash))
             |> Map.put("patient_id_hash", patient_id_hash)
             |> Map.put("user_id", user_id)
             |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(service_request_process_job) do
      {:ok, job}
    end
  end
end
