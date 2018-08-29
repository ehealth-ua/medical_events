defmodule AuditLogConsumer.Kafka.MongoEventConsumer do
  @moduledoc false

  use KafkaEx.GenConsumer
  alias Core.Mongo.AuditLog
  alias Core.Mongo.Event
  alias KafkaEx.Protocol.Fetch.Message
  require Logger

  # note - messages are delivered in batches
  def handle_message_set(message_set, state) do
    for %Message{value: message} <- message_set do
      value = :erlang.binary_to_term(message)
      Logger.debug(fn -> "message: " <> inspect(value) end)
      :ok = consume(value)
    end

    {:async_commit, state}
  end

  def consume(%Event{} = event) do
    AuditLog.store_event(event)
    :ok
  end

  def consume(value) do
    Logger.warn(fn -> "unknown kafka event: #{inspect(value)}" end)
    :ok
  end
end
