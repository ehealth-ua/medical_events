defmodule Core.Migrations.ServiceRequestsRequisitionNumberIntoHash do
  @moduledoc false

  alias Core.Encryptor
  alias Core.Mongo
  alias Core.ServiceRequest
  require Logger

  @collection ServiceRequest.metadata().collection

  def change do
    count =
      @collection
      |> Mongo.find(%{"requisition" => %{"$exists" => true}}, projection: %{"_id" => true, "requisition" => true})
      |> Enum.reduce(0, fn service_request, acc ->
        acc = acc + update_service_request(service_request)
      end)

    Logger.info("Service request requisition number convertation process finished: #{count} entities")
  end

  defp update_service_request(%{"_id" => id, "requisition" => requisition}) do
    case Mongo.update_one(@collection, %{"_id" => id}, %{"$set" => %{"requisition" => Encryptor.encrypt(requisition)}}) do
      {:ok, %{matched_count: 1, modified_count: 1}} ->
        1

      {:error, reason} ->
        raise "Failed to update service request (id: #{id}): #{inspect(reason)}"
    end
  end
end
