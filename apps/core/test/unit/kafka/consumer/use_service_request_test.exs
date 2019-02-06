defmodule Core.Kafka.Consumer.UseServiceRequestTest do
  @moduledoc false

  use Core.ModelCase
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.ServiceRequestUseJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  import Mox

  @status_pending Job.status(:pending)

  setup :verify_on_exit!

  describe "consume use service_request event" do
    test "success use service_request" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      job = insert(:job)

      service_request = insert(:service_request)
      %BSON.Binary{binary: id} = service_request._id
      employee_id = UUID.uuid4()

      expect(WorkerMock, :run, fn _, _, :employee_by_id, _ ->
        %{employee_type: "DOCTOR", status: "APPROVED", legal_entity_id: client_id}
      end)

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
               Consumer.consume(%ServiceRequestUseJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 service_request_id: UUID.binary_to_string!(id),
                 used_by: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => employee_id
                   }
                 }
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end

    test "fail on invalid drfo" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      job = insert(:job)

      service_request = insert(:service_request)
      %BSON.Binary{binary: id} = service_request._id
      employee_id = UUID.uuid4()

      expect(WorkerMock, :run, fn _, _, :employee_by_id, _ ->
        %{employee_type: "DOCTOR", status: "APPROVED", legal_entity_id: UUID.uuid4()}
      end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)
      user_id = UUID.uuid4()

      expect_job_update(
        job._id,
        %{
          invalid: [
            %{
              entry: "$.used_by.identifier.value",
              entry_type: "json_data_property",
              rules: [
                %{
                  description: "Employee #{employee_id} doesn't belong to your legal entity",
                  params: [],
                  rule: :invalid
                }
              ]
            }
          ],
          message:
            "Validation failed. You can find validators description at our API Manifest: http://docs.apimanifest.apiary.io/#introduction/interacting-with-api/errors.",
          type: :validation_failed
        },
        422
      )

      assert :ok =
               Consumer.consume(%ServiceRequestUseJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 service_request_id: UUID.binary_to_string!(id),
                 used_by: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
                     "value" => employee_id
                   }
                 }
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end
  end
end
