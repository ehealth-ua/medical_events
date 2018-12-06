use Mix.Config

config :kaffe,
  consumer: [
    endpoints: {:system, :string, "KAFKA_BROKERS"},
    topics: ["medical_events"],
    consumer_group: "medical_event_group",
    message_handler: EventConsumer.Kafka.MedicalEventConsumer
  ]
