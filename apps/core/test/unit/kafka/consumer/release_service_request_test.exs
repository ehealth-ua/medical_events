defmodule Core.Kafka.Consumer.ReleaseServiceRequestTest do
  @moduledoc false

  use Core.ModelCase
  alias Core.Job
  alias Core.Jobs.ServiceRequestReleaseJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  import Mox

  setup :verify_on_exit!

  describe "consume release service_request event" do
    test "success release service_request" do
      client_id = UUID.uuid4()
      job = insert(:job)

      service_request =
        insert(:service_request, used_by_employee: reference_coding(system: "eHealth/resources", code: "employee"))

      service_request_id = service_request._id

      %BSON.Binary{binary: id} = service_request_id
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
               Consumer.consume(%ServiceRequestReleaseJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 service_request_id: UUID.binary_to_string!(id)
               })
    end
  end

  test "fail on invalid expiration_date" do
    current_config = Application.get_env(:core, :service_request_expiration_days)
    expiration_days = 2

    on_exit(fn ->
      Application.put_env(:core, :service_request_expiration_days, current_config)
    end)

    Application.put_env(:core, :service_request_expiration_days, expiration_days)

    client_id = UUID.uuid4()
    now = DateTime.utc_now()
    job = insert(:job)

    service_request =
      insert(:service_request,
        used_by_employee: reference_coding(system: "eHealth/resources", code: "employee"),
        inserted_at: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * (expiration_days + 1)),
        expiration_date: DateTime.from_unix!(DateTime.to_unix(now) - 60 * 60 * 24 * expiration_days)
      )

    service_request_id = service_request._id

    %BSON.Binary{binary: id} = service_request_id
    patient_id = UUID.uuid4()
    patient_id_hash = Patients.get_pk_hash(patient_id)
    insert(:patient, _id: patient_id_hash)
    user_id = UUID.uuid4()

    expect(WorkerMock, :run, fn _, _, :transaction, args ->
      assert %{
               "actor_id" => _,
               "operations" => [
                 %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
               ]
             } = Jason.decode!(args)

      assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

      set_bson = set |> Base.decode64!() |> BSON.decode()
      status = Job.status(:failed)

      assert %{
               "$set" => %{
                 "status" => ^status,
                 "status_code" => 409,
                 "response" => "Service request is expired"
               }
             } = set_bson

      :ok
    end)

    assert :ok =
             Consumer.consume(%ServiceRequestReleaseJob{
               _id: to_string(job._id),
               patient_id: patient_id,
               patient_id_hash: patient_id_hash,
               user_id: user_id,
               client_id: client_id,
               service_request_id: UUID.binary_to_string!(id)
             })
  end
end
