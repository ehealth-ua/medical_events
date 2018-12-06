use Mix.Config

config :kaffe,
  consumer: [
    endpoints: {:system, :string, "KAFKA_BROKERS"},
    topics: ["secondary_events", "job_update_events"],
    consumer_group: "secondary_events_group",
    message_handler: SecondaryEventsConsumer.Kafka.Consumer
  ]
