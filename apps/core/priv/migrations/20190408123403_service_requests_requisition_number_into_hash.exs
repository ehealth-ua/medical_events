defmodule Core.Migrations.ServiceRequestsRequisitionNumberIntoHash do
  @moduledoc false

  alias Core.Encryptor
  alias Core.Mongo
  alias Core.Mongo.Transaction
  alias Core.ServiceRequest
  require Logger

  @collection ServiceRequest.metadata().collection

  def change do
    {successful_count, failed_count} =
      @collection
      |> Mongo.find(%{"requisition" => %{"$exists" => true}}, projection: %{"_id" => true, "requisition" => true})
      |> Enum.reduce({0, 0}, fn service_request, {successful_acc, failed_acc} ->
        {successful, failed} = update_service_request(service_request)
        {successful_acc + successful, failed_acc + failed}
      end)

    Logger.info(
      "Service request requisition number convertation process finished: successful - #{successful_count}, failed - #{
        failed_count
      }"
    )
  end

  defp update_service_request(%{"_id" => id, "requisition" => requisition}) do
    set = %{"requisition" => Encryptor.encrypt(requisition)}

    result =
      %Transaction{}
      |> Transaction.add_operation(@collection, :update, %{"_id" => id}, %{"$set" => set})
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
