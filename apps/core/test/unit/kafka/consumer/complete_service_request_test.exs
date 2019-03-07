defmodule Core.Kafka.Consumer.CompleteServiceRequestTest do
  @moduledoc false

  use Core.ModelCase
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.ServiceRequestCompleteJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  alias Core.ServiceRequest
  import Mox

  @status_pending Job.status(:pending)

  setup :verify_on_exit!

  describe "consume complete service_request event" do
    test "success complete service_request" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      job = insert(:job)

      service_request =
        insert(:service_request,
          status: ServiceRequest.status(:in_progress),
          used_by_legal_entity:
            build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(client_id)))
        )

      %BSON.Binary{binary: id} = service_request._id
      encounter = build(:encounter)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        encounters: %{
          UUID.binary_to_string!(encounter.id.binary) => encounter
        }
      )

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
               Consumer.consume(%ServiceRequestCompleteJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 service_request_id: UUID.binary_to_string!(id),
                 completed_with: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                     "value" => UUID.binary_to_string!(encounter.id.binary)
                   }
                 }
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end

    test "fail on invalid status" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      job = insert(:job)

      service_request = insert(:service_request)
      %BSON.Binary{binary: id} = service_request._id

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)
      user_id = UUID.uuid4()

      expect_job_update(
        job._id,
        Job.status(:failed),
        "Invalid service request status",
        409
      )

      assert :ok =
               Consumer.consume(%ServiceRequestCompleteJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 service_request_id: UUID.binary_to_string!(id),
                 completed_with: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                     "value" => UUID.uuid4()
                   }
                 }
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end

    test "fail on invalid used_by_legal_entity" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      job = insert(:job)

      service_request =
        insert(:service_request, status: ServiceRequest.status(:in_progress), used_by_legal_entity: build(:reference))

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
               Consumer.consume(%ServiceRequestCompleteJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 service_request_id: UUID.binary_to_string!(id),
                 completed_with: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                     "value" => UUID.uuid4()
                   }
                 }
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end

    test "fail on invalid completed_with reference" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      client_id = UUID.uuid4()
      job = insert(:job)

      service_request =
        insert(:service_request,
          status: ServiceRequest.status(:in_progress),
          used_by_legal_entity:
            build(:reference, identifier: build(:identifier, value: Mongo.string_to_uuid(client_id)))
        )

      %BSON.Binary{binary: id} = service_request._id

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)
      user_id = UUID.uuid4()

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "invalid" => [
            %{
              "entry" => "$.completed_with.identifier.value",
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Encounter with such id is not found",
                  "params" => [],
                  "rule" => "invalid"
                }
              ]
            }
          ],
          "message" =>
            "Validation failed. You can find validators description at our API Manifest: http://docs.apimanifest.apiary.io/#introduction/interacting-with-api/errors.",
          "type" => "validation_failed"
        },
        422
      )

      assert :ok =
               Consumer.consume(%ServiceRequestCompleteJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 service_request_id: UUID.binary_to_string!(id),
                 completed_with: %{
                   "identifier" => %{
                     "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                     "value" => UUID.uuid4()
                   }
                 }
               })

      assert {:ok, %Job{status: @status_pending}} = Jobs.get_by_id(to_string(job._id))
    end
  end
end
