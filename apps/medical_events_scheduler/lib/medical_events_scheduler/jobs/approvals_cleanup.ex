defmodule MedicalEventsScheduler.Jobs.ApprovalsCleanup do
  @moduledoc false

  use Confex, otp_app: :medical_events_scheduler

  alias Core.Approval
  alias Core.Mongo
  alias Core.Mongo.Transaction

  require Logger

  @collection Approval.metadata().collection

  def run do
    Logger.info("Approval cleanup process started")

    {successful_count, failed_count} =
      @collection
      |> Mongo.find(
        %{
          "status" => Approval.status(:new),
          "inserted_at" => %{
            "$lt" =>
              DateTime.add(
                DateTime.utc_now(),
                -1 * config()[:approval_ttl_hours] * 60 * 60,
                :second
              )
          }
        },
        projection: %{"_id" => true}
      )
      |> Enum.reduce({0, 0}, fn approval, {successful_acc, failed_acc} ->
        {successful, failed} = delete_approval(approval)
        {successful_acc + successful, failed_acc + failed}
      end)

    Logger.info("Approval cleanup process finished: successful - #{successful_count}, failed - #{failed_count}")
  end

  defp delete_approval(%{"_id" => id}) do
    updated_by = Confex.fetch_env!(:core, :system_user)

    result =
      %Transaction{actor_id: updated_by}
      |> Transaction.add_operation(@collection, :delete, %{"_id" => id}, id)
      |> Transaction.flush()

    case result do
      :ok ->
        {1, 0}

      {:error, reason} ->
        Logger.error("Failed to delete approval (id: #{id}): #{inspect(reason)}")
        {0, 1}
    end
  end
end
