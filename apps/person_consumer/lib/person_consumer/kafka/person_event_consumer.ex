defmodule PersonConsumer.Kafka.PersonEventConsumer do
  @moduledoc false

  use KafkaEx.GenConsumer
  alias Core.Mongo
  alias Core.Patient
  alias KafkaEx.Protocol.Fetch.Message
  require Logger

  @status_active Patient.status(:active)
  @status_inactive Patient.status(:inactive)

  # note - messages are delivered in batches
  def handle_message_set(message_set, state) do
    for %Message{value: message} <- message_set do
      value = :erlang.binary_to_term(message)
      Logger.debug(fn -> "message: " <> inspect(value) end)
      :ok = consume(value)
    end

    {:async_commit, state}
  end

  def consume(%{"id" => person_id, "status" => status, "updated_by" => updated_by})
      when status in [@status_active, @status_inactive] do
    Mongo.update_one(
      Patient.metadata().collection,
      %{"_id" => person_id},
      %{"$set" => %{"status" => status, "updated_by" => updated_by}},
      upsert: true
    )

    :ok
  end

  def consume(value) do
    Logger.warn(fn -> "unknown kafka event: #{inspect(value)}" end)
    :ok
  end
end
