defmodule MedicalEventsScheduler.Jobs.ServiceRequestAutoexpiration do
  @moduledoc false

  use Confex, otp_app: :medical_events_scheduler

  alias Core.Mongo
  alias Core.Mongo.Transaction
  alias Core.ServiceRequest
  alias Core.StatusHistory

  require Logger

  @collection ServiceRequest.metadata().collection

  def run do
    Logger.info("Service request autoexpiration process started")

    {successful_count, failed_count} =
      @collection
      |> Mongo.find(
        %{
          "status" => ServiceRequest.status(:active),
          "expiration_date" => %{"$lt" => DateTime.utc_now()}
        },
        projection: %{"_id" => true}
      )
      |> Enum.reduce({0, 0}, fn service_request, {successful_acc, failed_acc} ->
        {successful, failed} = update_service_request(service_request)
        {successful_acc + successful, failed_acc + failed}
      end)

    Logger.info(
      "Service request autoexpiration process finished: successful - #{successful_count}, failed - #{failed_count}"
    )
  end

  defp update_service_request(%{"_id" => id}) do
    updated_at = DateTime.utc_now()
    updated_by = Confex.fetch_env!(:core, :system_user)

    set =
      %{
        "updated_by" => updated_by,
        "updated_at" => updated_at,
        "status" => ServiceRequest.status(:cancelled),
        "status_reason" => %{
          "coding" => [%{"system" => "eHealth/service_request_cancel_reasons", "code" => "autoexpired"}],
          "text" => nil
        }
      }
      |> Mongo.convert_to_uuid("updated_by")

    status_history =
      StatusHistory.create(%{
        "status" => ServiceRequest.status(:cancelled),
        "status_reason" => %{
          "coding" => [%{"system" => "eHealth/service_request_cancel_reasons", "code" => "autoexpired"}],
          "text" => nil
        },
        "inserted_at" => updated_at,
        "inserted_by" => Mongo.string_to_uuid(updated_by)
      })

    push = Mongo.add_to_push(%{}, status_history, "status_history")

    result =
      %Transaction{}
      |> Transaction.add_operation(@collection, :update, %{"_id" => id}, %{"$set" => set, "$push" => push})
      |> Transaction.flush()

    case result do
      :ok ->
        {1, 0}

      {:error, reason} ->
        Logger.error("Failed to update service request (id: #{id}): #{inspect(reason)}")
        {0, 1}
    end
  end
end
