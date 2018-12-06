use Mix.Config

config :audit_log_consumer,
  kaffe_consumer: [
    endpoints: {:system, :string, "KAFKA_BROKERS"},
    topics: ["mongo_events"],
    consumer_group: "mongo_event_group",
    message_handler: AuditLogConsumer.Kafka.MongoEventConsumer
  ]
