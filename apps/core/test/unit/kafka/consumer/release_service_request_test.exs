defmodule Core.Kafka.Consumer.ReleaseServiceRequestTest do
  @moduledoc false

  use Core.ModelCase
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.ServiceRequestReleaseJob
  alias Core.Kafka.Consumer
  alias Core.Mongo
  alias Core.Patients
  import Mox

  @status_pending Job.status(:pending)

  setup :verify_on_exit!

  describe "consume release service_request event" do
    test "success release service_request" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      job = insert(:job)

      service_request =
        insert(:service_request, used_by: reference_coding(system: "eHealth/resources", code: "employee"))

      service_request_id = service_request._id

      %BSON.Binary{binary: id} = service_request_id
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

      assert :ok =
               Consumer.consume(%ServiceRequestReleaseJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 service_request_id: UUID.binary_to_string!(id)
               })

      assert %{"_id" => ^service_request_id, "used_by" => nil} =
               Mongo.find_one("service_requests", %{_id: service_request_id})

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end
  end
end
