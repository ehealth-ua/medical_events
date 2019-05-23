defmodule Core.Kafka.Consumer.CloseServiceRequestTest do
  @moduledoc false

  use Core.ModelCase
  alias Core.Job
  alias Core.Jobs.ServiceRequestCloseJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  alias Core.ServiceRequest
  import Mox

  setup :verify_on_exit!

  describe "consume close service_request event" do
    test "success close service_request" do
      client_id = UUID.uuid4()
      job = insert(:job)

      service_request = insert(:service_request)
      %BSON.Binary{binary: id} = service_request._id
      id = UUID.binary_to_string!(id)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)
      user_id = UUID.uuid4()

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [
                   %{"collection" => "service_requests", "operation" => "update_one"},
                   %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
                 ]
               } = Jason.decode!(args)

        assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

        set_bson = set |> Base.decode64!() |> BSON.decode()

        status = Job.status(:processed)

        response = %{
          "links" => [
            %{
              "entity" => "service_request",
              "href" => "/api/patients/#{patient_id}/service_requests/#{service_request._id}"
            }
          ]
        }

        assert %{
                 "$set" => %{
                   "status" => ^status,
                   "status_code" => 200,
                   "response" => ^response
                 }
               } = set_bson

        :ok
      end)

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
    end

    test "can't close service_request with invalid status" do
      client_id = UUID.uuid4()
      job = insert(:job)

      service_request = insert(:service_request, status: ServiceRequest.status(:recalled))
      %BSON.Binary{binary: id} = service_request._id
      id = UUID.binary_to_string!(id)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)
      user_id = UUID.uuid4()

      expect_job_update(job._id, Job.status(:failed), "Service request with status recalled can't be closed", 409)

      assert service_request.status == ServiceRequest.status(:recalled)

      assert :ok =
               Consumer.consume(%ServiceRequestCloseJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 id: id
               })
    end
  end
end
