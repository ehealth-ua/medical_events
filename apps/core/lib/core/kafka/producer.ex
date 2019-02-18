defmodule Core.Kafka.Producer do
  @moduledoc false

  alias Core.Mongo.Event
  require Logger

  @medical_events_topic "medical_events"
  @mongo_events_topic "mongo_events"

  @behaviour Core.Behaviours.KafkaProducerBehaviour

  def publish_medical_event(request) do
    partition = get_partition(request.patient_id, @medical_events_topic)
    key = get_key(request.patient_id)
    Logger.info("Publishing kafka event to topic: #{@medical_events_topic}, partition: #{partition}, key: #{key}")
    Kaffe.Producer.produce_sync(@medical_events_topic, partition, key, :erlang.term_to_binary(request))
  end

  def publish_mongo_event(%Event{} = event) do
    partition = get_partition(event.actor_id, @mongo_events_topic)
    key = get_key(event.actor_id)
    Logger.info("Publishing kafka event to topic: #{@mongo_events_topic}, partition: #{partition}, key: #{key}")
    Kaffe.Producer.produce_sync(@mongo_events_topic, partition, key, :erlang.term_to_binary(event))
  end

  defp get_key(%BSON.Binary{binary: id}) do
    UUID.binary_to_string!(id)
  end

  defp get_key(value), do: value

  defp get_partition(nil, _), do: 0
  defp get_partition("", _), do: 0

  defp get_partition(%BSON.Binary{binary: id}, topic) do
    get_partition(UUID.binary_to_string!(id), topic)
  end

  defp get_partition(patient_id, topic) do
    partitions_number = Confex.fetch_env!(:core, :kafka)[:partitions][topic] - 1
    {i, _} = Integer.parse(String.first(patient_id), 16)
    trunc(i * partitions_number / 12)
  end
end
