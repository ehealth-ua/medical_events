use Mix.Config

config :secondary_events_consumer,
  kaffe_consumer: [
    endpoints: [localhost: 9092],
    topics: ["secondary_events", "job_update_events"],
    consumer_group: "secondary_events_group",
    message_handler: SecondaryEventsConsumer.Kafka.Consumer
  ]

import_config "#{Mix.env()}.exs"
