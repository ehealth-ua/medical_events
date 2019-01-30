defmodule Core.Kafka.Consumer.CloseServiceRequestTest do
  @moduledoc false

  use Core.ModelCase
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.ServiceRequestCloseJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  alias Core.ServiceRequest
  alias Core.ServiceRequests
  import Mox

  @status_pending Job.status(:pending)

  setup :verify_on_exit!

  describe "consume close service_request event" do
    test "success close service_request" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      job = insert(:job)

      service_request = insert(:service_request)
      %BSON.Binary{binary: id} = service_request._id
      id = UUID.binary_to_string!(id)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)
      user_id = UUID.uuid4()

      expect_job_update(
        job._id,
        %{
          "links" => [
            %{
              "entity" => "service_request",
              "href" => "/api/patients/#{patient_id}/service_requests/#{service_request._id}"
            }
          ]
        },
        200
      )

      assert service_request.status == ServiceRequest.status(:active)

      assert :ok =
               Consumer.consume(%ServiceRequestCloseJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 id: id
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
      assert {:ok, service_request} = ServiceRequests.get_by_id(id)
      assert service_request.status == ServiceRequest.status(:completed)
    end

    test "can't close service_request with invalid status" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      job = insert(:job)

      service_request = insert(:service_request, status: ServiceRequest.status(:cancelled))
      %BSON.Binary{binary: id} = service_request._id
      id = UUID.binary_to_string!(id)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)
      user_id = UUID.uuid4()

      expect_job_update(job._id, "Service request with status cancelled can't be closed", 409)

      assert service_request.status == ServiceRequest.status(:cancelled)

      assert :ok =
               Consumer.consume(%ServiceRequestCloseJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 id: id
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
      assert {:ok, service_request} = ServiceRequests.get_by_id(id)
      assert service_request.status == ServiceRequest.status(:cancelled)
    end
  end
end
