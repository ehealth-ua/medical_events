defmodule Core.Kafka.Producer do
  @moduledoc false

  alias Core.Mongo.Event

  @medical_events_topic "medical_events"

  @mongo_events_topic "mongo_events"

  @behaviour Core.Behaviours.KafkaProducerBehaviour

  def publish_medical_event(request) do
    KafkaEx.produce(@medical_events_topic, 0, :erlang.term_to_binary(request))
  end

  def publish_mongo_event(%Event{} = event) do
    KafkaEx.produce(@mongo_events_topic, 0, :erlang.term_to_binary(event))
  end
end
