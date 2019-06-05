defmodule EventConsumer.Kafka.MedicalEventConsumer do
  @moduledoc false

  alias Core.Kafka.Consumer
  require Logger

  def handle_messages(messages) do
    for %{offset: offset, value: value} <- messages do
      value = :erlang.binary_to_term(value)
      Logger.metadata(request_id: value.request_id, job_id: value._id)
      Logger.debug(fn -> "message: " <> inspect(value) end)
      Logger.info(fn -> "offset: #{offset}" end)
      :ok = Consumer.consume(value)
    end

    :ok
  end
end
