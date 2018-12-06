use Mix.Config

config :audit_log_consumer,
  kaffe_consumer: [
    endpoints: [localhost: 9092],
    topics: ["mongo_events"],
    consumer_group: "mongo_event_group",
    message_handler: AuditLogConsumer.Kafka.MongoEventConsumer
  ]

import_config "#{Mix.env()}.exs"
