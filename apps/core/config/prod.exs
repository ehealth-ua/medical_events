use Mix.Config

# Configuration for production environment.
# It should read environment variables to follow 12 factor apps convention.

config :core, :mongo, url: "${DB_URL}"
config :core, :mongo_audit_log, url: "${AUDIT_LOG_DB_URL}"

config :kaffe,
  producer: [
    endpoints: {:system, :string, "KAFKA_BROKERS"},
    topics: ["medical_events", "secondary_events", "job_update_events", "mongo_events"]
  ]

config :kafka_ex, brokers: {:system, :string, "KAFKA_BROKERS"}
