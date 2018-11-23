defmodule Core.Kafka.Consumer.UseServiceRequestTest do
  @moduledoc false

  use Core.ModelCase
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.ServiceRequestUseJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  import Mox

  @status_processed Job.status(:processed)

  describe "consume use service_request event" do
    test "success use service_request" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      job = insert(:job)

      service_request = insert(:service_request)
      %BSON.Binary{binary: id} = service_request._id
      employee_id = UUID.uuid4()

      expect(WorkerMock, :run, 2, fn
        _, _, :employees_by_user_id_client_id, _ -> [employee_id]
        _, _, :tax_id_by_employee_id, _ -> "1111111112"
        _, _, :employee_by_id, _ -> %{status: "APPROVED", legal_entity: %{id: client_id}}
      end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)
      user_id = UUID.uuid4()

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

      assert {:ok,
              %Core.Job{
                response_size: 154,
                status: @status_processed
              }} = Jobs.get_by_id(to_string(job._id))
    end

    test "fail on invalid drfo" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      job = insert(:job)

      service_request = insert(:service_request)
      %BSON.Binary{binary: id} = service_request._id
      employee_id = UUID.uuid4()

      expect(WorkerMock, :run, 2, fn
        _, _, :employees_by_user_id_client_id, _ -> [employee_id]
        _, _, :tax_id_by_employee_id, _ -> "1111111113"
        _, _, :employee_by_id, _ -> %{status: "APPROVED", legal_entity: %{id: UUID.uuid4()}}
      end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)
      user_id = UUID.uuid4()

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

      assert {:ok,
              %Core.Job{
                response_size: 417,
                status: @status_processed
              }} = Jobs.get_by_id(to_string(job._id))
    end
  end
end
