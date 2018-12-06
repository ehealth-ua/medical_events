defmodule AuditLogConsumer.Kafka.MongoEventConsumer do
  @moduledoc false

  alias Core.Mongo.AuditLog
  alias Core.Mongo.Event
  require Logger

  def handle_message_set(%{key: key, value: value} = message) do
    value = :erlang.binary_to_term(value)
    Logger.debug(fn -> "message: " <> inspect(value) end)
    Logger.info(fn -> "offset: #{Map.get(message, :offset)}" end)
    :ok = consume(value)
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
