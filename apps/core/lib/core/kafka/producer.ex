defmodule Core.Kafka.Producer do
  @moduledoc false

  alias Core.Request

  @medical_events_topic "medical_events"

  def publish_medical_event(%Request{_id: id}, data) do
    KafkaEx.produce(@medical_events_topic, 0, :erlang.term_to_binary(%{id: id, data: data}))
  end
end
