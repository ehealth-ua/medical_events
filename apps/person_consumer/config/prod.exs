use Mix.Config

config :person_consumer,
  kaffe_consumer: [
    endpoints: {:system, :string, "KAFKA_BROKERS"},
    topics: ["person_events"],
    consumer_group: "person_events_group",
    message_handler: PersonConsumer.Kafka.PersonEventConsumer,
    max_bytes: {:system, :integer, "PERSON_CONSUMER_BATCH_MAX_BYTES", 500_000}
  ]
