use Mix.Config

config :kaffe,
  consumer: [
    endpoints: [localhost: 9092],
    topics: ["mongo_events"],
    consumer_group: "mongo_event_group",
    message_handler: AuditLogConsumer.Kafka.MongoEventConsumer
  ]

import_config "#{Mix.env()}.exs"
