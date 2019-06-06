defmodule MedicalEventsScheduler.Jobs.JobsCleanupTest do
  @moduledoc false

  use ExUnit.Case

  import Core.Factories
  import ExUnit.CaptureLog
  import Mox

  alias Core.Job
  alias Core.Mongo
  alias MedicalEventsScheduler.Jobs.JobsCleanup

  @collection Job.collection()

  setup :verify_on_exit!

  setup do
    Mongo.delete_many!(@collection, %{})
    :ok
  end

  test "success jobs clean up" do
    job_deletion_days = Confex.fetch_env!(:medical_events_scheduler, JobsCleanup)[:job_ttl_days]
    now = DateTime.utc_now()

    insert(:job, status: Job.status(:processed), inserted_at: now, updated_at: now)

    insert(:job,
      status: Job.status(:pending),
      inserted_at: DateTime.add(now, -1 * (job_deletion_days + 1) * 60 * 60 * 24, :second),
      updated_at: DateTime.add(now, -1 * (job_deletion_days + 1) * 60 * 60 * 24, :second)
    )

    job_deleted_processed =
      insert(:job,
        status: Job.status(:processed),
        inserted_at: DateTime.add(now, -1 * (job_deletion_days + 1) * 60 * 60 * 24, :second),
        updated_at: DateTime.add(now, -1 * (job_deletion_days + 1) * 60 * 60 * 24, :second)
      )

    job_deleted_failed =
      insert(:job,
        status: Job.status(:failed),
        inserted_at: DateTime.add(now, -1 * (job_deletion_days + 1) * 60 * 60 * 24, :second),
        updated_at: DateTime.add(now, -1 * (job_deletion_days + 1) * 60 * 60 * 24, :second)
      )

    job_deleted_failed_with_error =
      insert(:job,
        status: Job.status(:failed_with_error),
        inserted_at: DateTime.add(now, -1 * (job_deletion_days + 1) * 60 * 60 * 24, :second),
        updated_at: DateTime.add(now, -1 * (job_deletion_days + 1) * 60 * 60 * 24, :second)
      )

    deleted_list = [job_deleted_processed, job_deleted_failed, job_deleted_failed_with_error]

    Enum.each(deleted_list, fn job ->
      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [%{"collection" => @collection, "operation" => "delete_one", "filter" => filter}]
               } = Jason.decode!(args)

        filter_bson = filter |> Base.decode64!() |> BSON.decode()
        job_id = job._id
        assert %{"_id" => ^job_id} = filter_bson

        :ok
      end)
    end)

    JobsCleanup.run()
  end

  test "jobs clean up failed" do
    job_deletion_days = Confex.fetch_env!(:medical_events_scheduler, JobsCleanup)[:job_ttl_days]
    now = DateTime.utc_now()

    %{_id: id} =
      insert(:job,
        status: Job.status(:processed),
        inserted_at: DateTime.add(now, -1 * (job_deletion_days + 1) * 60 * 60 * 24, :second),
        updated_at: DateTime.add(now, -1 * (job_deletion_days + 1) * 60 * 60 * 24, :second)
      )

    expect(WorkerMock, :run, fn _, _, :transaction, _args ->
      {:error, :badrpc}
    end)

    assert capture_log(fn -> JobsCleanup.run() end) =~ "Failed to delete job (id: #{id})"
  end
end
