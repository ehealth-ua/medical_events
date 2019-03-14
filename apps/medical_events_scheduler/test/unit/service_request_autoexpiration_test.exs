defmodule MedicalEventsScheduler.Jobs.ServiceRequestAutoexpirationTest do
  @moduledoc false

  use ExUnit.Case

  import Core.Factories
  import ExUnit.CaptureLog
  import Mox

  alias Core.Mongo
  alias Core.ServiceRequest
  alias MedicalEventsScheduler.Jobs.ServiceRequestAutoexpiration

  @collection ServiceRequest.metadata().collection

  setup :verify_on_exit!

  setup do
    Mongo.delete_many!(@collection, %{})
    :ok
  end

  test "success service requests autoexpiration" do
    stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

    service_request_not_updated_1 =
      insert(:service_request, status: ServiceRequest.status(:active), expiration_date: expiration_date_from_now(1))

    service_request_not_updated_2 =
      insert(:service_request,
        status: ServiceRequest.status(:in_progress),
        expiration_date: expiration_date_from_now(-1)
      )

    service_request_updated =
      insert(:service_request, status: ServiceRequest.status(:active), expiration_date: expiration_date_from_now(-1))

    not_updated_list = [service_request_not_updated_1, service_request_not_updated_2]
    updated_list = [service_request_updated]
    status_cancelled = ServiceRequest.status(:cancelled)

    user_id =
      :core
      |> Confex.fetch_env!(:system_user)
      |> Mongo.string_to_uuid()

    expect(WorkerMock, :run, fn _, _, :transaction, args ->
      assert [%{"collection" => @collection, "operation" => "update_one", "filter" => filter, "set" => set}] =
               Jason.decode!(args)

      filter_bson = filter |> Base.decode64!() |> BSON.decode()

      set_bson =
        set
        |> Base.decode64!()
        |> BSON.decode()

      Enum.each(updated_list, fn service_request ->
        service_request_id = service_request._id

        assert %{"_id" => ^service_request_id} = filter_bson

        assert %{
                 "$push" => %{
                   "status_history" => %{
                     "inserted_by" => ^user_id,
                     "status" => ^status_cancelled,
                     "status_reason" => %{
                       "coding" => [
                         %{
                           "code" => "autoexpired",
                           "system" => "eHealth/service_request_cancel_reasons"
                         }
                       ],
                       "text" => nil
                     }
                   }
                 },
                 "$set" => %{
                   "status" => ^status_cancelled,
                   "status_reason" => %{
                     "coding" => [
                       %{
                         "code" => "autoexpired",
                         "system" => "eHealth/service_request_cancel_reasons"
                       }
                     ],
                     "text" => nil
                   },
                   "updated_by" => ^user_id
                 }
               } = set_bson
      end)

      Enum.each(not_updated_list, fn service_request ->
        refute %{"_id" => service_request._id} == filter_bson
      end)

      :ok
    end)

    ServiceRequestAutoexpiration.run()
  end

  test "service requests autoexpiration failed" do
    stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

    %{_id: id} =
      insert(:service_request, status: ServiceRequest.status(:active), expiration_date: expiration_date_from_now(-1))

    expect(WorkerMock, :run, fn _, _, :transaction, _args ->
      {:error, :badrpc}
    end)

    assert capture_log(fn -> ServiceRequestAutoexpiration.run() end) =~ "Failed to update service request (id: #{id})"
  end

  defp expiration_date_from_now(shift_days) do
    now = DateTime.utc_now()
    expiration_erl_date = now |> DateTime.to_date() |> Date.add(shift_days) |> Date.to_erl()

    {expiration_erl_date, {23, 59, 59}}
    |> NaiveDateTime.from_erl!()
    |> DateTime.from_naive!("Etc/UTC")
  end
end
