use Mix.Config

config :kaffe,
  consumer: [
    endpoints: {:system, :string, "KAFKA_BROKERS"},
    topics: ["person_events"],
    consumer_group: "person_events_group",
    message_handler: PersonConsumer.Kafka.PersonEventConsumer
  ]
