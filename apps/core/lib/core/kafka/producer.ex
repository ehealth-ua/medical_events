defmodule Core.Kafka.Producer do
  @moduledoc false

  alias Core.Mongo.Event

  @medical_events_topic "medical_events"
  @secondary_events_topic "secondary_events"
  @job_update_events_topic "job_update_events"
  @mongo_events_topic "mongo_events"

  @behaviour Core.Behaviours.KafkaProducerBehaviour

  def publish_medical_event(request) do
    Kaffe.Producer.produce_sync(
      @medical_events_topic,
      get_partition(request.patient_id, @medical_events_topic),
      request.patient_id,
      :erlang.term_to_binary(request)
    )
  end

  def publish_encounter_package_event(event) do
    Kaffe.Producer.produce_sync(
      @secondary_events_topic,
      get_partition(event.patient_id, @secondary_events_topic),
      event.patient_id,
      :erlang.term_to_binary(event)
    )
  end

  def publish_mongo_event(%Event{} = event) do
    Kaffe.Producer.produce_sync(
      @mongo_events_topic,
      get_partition(event.actor_id, @mongo_events_topic),
      event.actor_id,
      :erlang.term_to_binary(event)
    )
  end

  def publish_job_update_status_event(event) do
    Kaffe.Producer.produce_sync(
      @job_update_events_topic,
      Enum.random(0..Confex.fetch_env!(:core, :kafka)[:partitions][@job_update_events_topic]),
      UUID.uuid4(),
      :erlang.term_to_binary(event)
    )
  end

  defp get_partition(nil, _), do: 0
  defp get_partition("", _), do: 0

  defp get_partition(%BSON.Binary{binary: id}, topic) do
    get_partition(UUID.binary_to_string!(id), topic)
  end

  defp get_partition(patient_id, topic) do
    partitions_number = Confex.fetch_env!(:core, :kafka)[:partitions][topic]
    {i, _} = Integer.parse(String.first(patient_id), 16)
    trunc((i + 1) * partitions_number / 16)
  end
end
