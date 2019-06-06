defmodule MedicalEventsScheduler.Jobs.JobsCleanup do
  @moduledoc false

  use Confex, otp_app: :medical_events_scheduler

  alias Core.Job
  alias Core.Mongo
  alias Core.Mongo.Transaction

  require Logger

  @collection Job.collection()

  def run do
    Logger.info("Job cleanup process started")

    {successful_count, failed_count} =
      @collection
      |> Mongo.find(
        %{
          "status" => %{"$ne" => Job.status(:pending)},
          "updated_at" => %{
            "$lt" =>
              DateTime.add(
                DateTime.utc_now(),
                -1 * config()[:job_ttl_days] * 60 * 60 * 24,
                :second
              )
          }
        },
        projection: %{"_id" => true}
      )
      |> Enum.reduce({0, 0}, fn job, {successful_acc, failed_acc} ->
        {successful, failed} = delete_job(job)
        {successful_acc + successful, failed_acc + failed}
      end)

    Logger.info("Job cleanup process finished: successful - #{successful_count}, failed - #{failed_count}")
  end

  defp delete_job(%{"_id" => id}) do
    updated_by = Confex.fetch_env!(:core, :system_user)

    result =
      %Transaction{actor_id: updated_by}
      |> Transaction.add_operation(@collection, :delete, %{"_id" => id}, id)
      |> Transaction.flush()

    case result do
      :ok ->
        {1, 0}

      {:error, reason} ->
        Logger.error("Failed to delete job (id: #{id}): #{inspect(reason)}")
        {0, 1}
    end
  end
end
