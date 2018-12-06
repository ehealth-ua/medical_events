defmodule EventConsumer.Kafka.MedicalEventConsumer do
  @moduledoc false

  alias Core.Kafka.Consumer
  require Logger

  def handle_message_set(%{key: key, value: value} = message) do
    value = :erlang.binary_to_term(message)
    Logger.debug(fn -> "message: " <> inspect(value) end)
    Logger.info(fn -> "offset: #{Map.get(message, :offset)}" end)
    :ok = Consumer.consume(value)
  end
end
