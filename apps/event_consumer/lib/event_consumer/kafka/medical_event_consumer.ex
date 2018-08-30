defmodule EventConsumer.Kafka.MedicalEventConsumer do
  @moduledoc false

  use KafkaEx.GenConsumer
  alias Core.Kafka.Consumer
  alias KafkaEx.Protocol.Fetch.Message
  require Logger

  # note - messages are delivered in batches
  def handle_message_set(message_set, state) do
    for %Message{value: message, offset: offset} <- message_set do
      value = :erlang.binary_to_term(message)
      Logger.debug(fn -> "message: " <> inspect(value) end)
      Logger.info(fn -> "offset: " <> offset end)
      :ok = Consumer.consume(value)
    end

    {:async_commit, state}
  end
end
