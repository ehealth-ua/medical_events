defmodule Core.Kafka.Consumer.ProcessServiceRequestTest do
  @moduledoc false

  use Core.ModelCase
  alias Core.Job
  alias Core.Jobs.ServiceRequestProcessJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  alias Core.ServiceRequest
  import Mox

  setup :verify_on_exit!

  describe "consume process service_request event" do
    test "success process service_request" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      job = insert(:job)

      service_request =
        insert(:service_request,
          used_by_legal_entity:
            build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(client_id)))
        )

      %BSON.Binary{binary: id} = service_request._id
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)
      user_id = UUID.uuid4()

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert [
                 %{"collection" => "service_requests", "operation" => "update_one"},
                 %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
               ] = Jason.decode!(args)

        assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

        set_bson = set |> Base.decode64!() |> BSON.decode()

        response = %{
          "links" => [
            %{
              "entity" => "service_request",
              "href" => "/api/patients/#{patient_id}/service_requests/#{service_request._id}"
            }
          ]
        }

        status = Job.status(:processed)

        assert %{
                 "$set" => %{
                   "status" => ^status,
                   "status_code" => 200,
                   "response" => ^response
                 }
               } = set_bson

        :ok
      end)

      assert :ok =
               Consumer.consume(%ServiceRequestProcessJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 service_request_id: UUID.binary_to_string!(id)
               })
    end
  end

  test "fail on invalid status" do
    stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

    client_id = UUID.uuid4()
    job = insert(:job)

    service_request = insert(:service_request, status: ServiceRequest.status(:completed))

    service_request_id = service_request._id

    %BSON.Binary{binary: id} = service_request_id
    patient_id = UUID.uuid4()
    patient_id_hash = Patients.get_pk_hash(patient_id)
    insert(:patient, _id: patient_id_hash)
    user_id = UUID.uuid4()

    expect(WorkerMock, :run, fn _, _, :transaction, args ->
      assert [%{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}] =
               Jason.decode!(args)

      assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

      set_bson = set |> Base.decode64!() |> BSON.decode()
      status = Job.status(:failed)

      assert %{
               "$set" => %{
                 "status" => ^status,
                 "status_code" => 409,
                 "response" => "Invalid service request status"
               }
             } = set_bson

      :ok
    end)

    assert :ok =
             Consumer.consume(%ServiceRequestProcessJob{
               _id: to_string(job._id),
               patient_id: patient_id,
               patient_id_hash: patient_id_hash,
               user_id: user_id,
               client_id: client_id,
               service_request_id: UUID.binary_to_string!(id)
             })
  end

  test "fail on invalid used_by_legal_entity" do
    stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
    client_id = UUID.uuid4()
    job = insert(:job)

    service_request = insert(:service_request, used_by_legal_entity: build(:reference))

    %BSON.Binary{binary: id} = service_request._id

    patient_id = UUID.uuid4()
    patient_id_hash = Patients.get_pk_hash(patient_id)
    insert(:patient, _id: patient_id_hash)
    user_id = UUID.uuid4()

    expect_job_update(
      job._id,
      Job.status(:failed),
      "Service request is used by another legal entity",
      409
    )

    assert :ok =
             Consumer.consume(%ServiceRequestProcessJob{
               _id: to_string(job._id),
               patient_id: patient_id,
               patient_id_hash: patient_id_hash,
               user_id: user_id,
               client_id: client_id,
               service_request_id: UUID.binary_to_string!(id)
             })
  end
end
