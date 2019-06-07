use Mix.Config

config :event_consumer,
  kaffe_consumer: [
    endpoints: {:system, :string, "KAFKA_BROKERS"},
    topics: ["medical_events"],
    consumer_group: "medical_event_group",
    message_handler: EventConsumer.Kafka.MedicalEventConsumer,
    max_bytes: {:system, :integer, "EVENT_CONSUMER_BATCH_MAX_BYTES", 500_000}
  ]
