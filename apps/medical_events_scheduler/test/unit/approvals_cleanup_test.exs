defmodule MedicalEventsScheduler.Jobs.ApprovalsCleanupTest do
  @moduledoc false

  use ExUnit.Case

  import Core.Factories
  import ExUnit.CaptureLog
  import Mox

  alias Core.Mongo
  alias Core.Approval
  alias MedicalEventsScheduler.Jobs.ApprovalsCleanup

  @collection Approval.collection()

  setup :verify_on_exit!

  setup do
    Mongo.delete_many!(@collection, %{})
    :ok
  end

  test "success approvals clean up" do
    approval_deletion_hours = Confex.fetch_env!(:medical_events_scheduler, ApprovalsCleanup)[:approval_ttl_hours]

    now = DateTime.utc_now()

    insert(:approval, status: Approval.status(:new), inserted_at: now)

    insert(:approval,
      status: Approval.status(:active),
      inserted_at: DateTime.add(now, -1 * (approval_deletion_hours + 1) * 60 * 60, :second)
    )

    approval_deleted =
      insert(:approval,
        status: Approval.status(:new),
        inserted_at: DateTime.add(now, -1 * (approval_deletion_hours + 1) * 60 * 60, :second)
      )

    deleted_list = [approval_deleted]

    Enum.each(deleted_list, fn approval ->
      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [%{"collection" => @collection, "operation" => "delete_one", "filter" => filter}]
               } = Jason.decode!(args)

        filter_bson = filter |> Base.decode64!() |> BSON.decode()
        approval_id = approval._id
        assert %{"_id" => ^approval_id} = filter_bson

        :ok
      end)
    end)

    ApprovalsCleanup.run()
  end

  test "approvals clean up failed" do
    approval_deletion_hours = Confex.fetch_env!(:medical_events_scheduler, ApprovalsCleanup)[:approval_ttl_hours]

    %{_id: id} =
      insert(:approval,
        status: Approval.status(:new),
        inserted_at: DateTime.add(DateTime.utc_now(), -1 * (approval_deletion_hours + 1) * 60 * 60, :second)
      )

    expect(WorkerMock, :run, fn _, _, :transaction, _args ->
      {:error, :badrpc}
    end)

    assert capture_log(fn -> ApprovalsCleanup.run() end) =~ "Failed to delete approval (id: #{id})"
  end
end
