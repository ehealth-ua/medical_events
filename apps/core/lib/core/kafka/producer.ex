defmodule Core.Kafka.Producer do
  @moduledoc false

  require Logger

  @medical_events_topic "medical_events"
  @event_manager_topic "event_manager_topic"

  @behaviour Core.Behaviours.KafkaProducerBehaviour

  def publish_to_event_manager(%{} = event),
    do: Kaffe.Producer.produce_sync(@event_manager_topic, 0, "", :erlang.term_to_binary(event))

  def publish_medical_event(request) do
    key = get_key(request.patient_id)
    Logger.info("Publishing kafka event to topic: #{@medical_events_topic}, key: #{key}")
    Kaffe.Producer.produce_sync(@medical_events_topic, key, :erlang.term_to_binary(request))
  end

  defp get_key(%BSON.Binary{binary: id}) do
    UUID.binary_to_string!(id)
  end

  defp get_key(value), do: value
end
