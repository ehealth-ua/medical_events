defmodule Core.Kafka.Producer do
  @moduledoc false

  @medical_events_topic "medical_events"
  @behaviour Core.Behaviours.KafkaProducerBehaviour

  def publish_medical_event(request) do
    KafkaEx.produce(@medical_events_topic, 0, :erlang.term_to_binary(request))
  end
end
