defmodule Core.Migrations.ServiceRequestsRequisitionNumberIntoHash do
  @moduledoc false

  alias Core.Encryptor
  alias Core.Mongo
  alias Core.Mongo.Transaction
  alias Core.ServiceRequest

  @collection ServiceRequest.metadata().collection

  def change do
    @collection
    |> Mongo.find(%{"requisition" => %{"$exists" => true}}, projection: %{"_id" => true, "requisition" => true})
    |> Enum.each(&update_service_request/1)
  end

  defp update_service_request(%{"_id" => id, "requisition" => requisition}) do
    set = %{"requisition" => Encryptor.encrypt(requisition)}

    result =
      %Transaction{}
      |> Transaction.add_operation(@collection, :update, %{"_id" => id}, %{"$set" => set})
      |> Transaction.flush()

    case result do
      :ok ->
        :ok

      {:error, reason} ->
        raise "Failed to process migration: #{inspect(reason)}"
    end
  end
end
