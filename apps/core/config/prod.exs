use Mix.Config

# Configuration for production environment.
# It should read environment variables to follow 12 factor apps convention.

config :core, :mongo,
  url: {:system, :string, "DB_URL"},
  pool_size: {:system, :integer, "DB_POOL_SIZE", 10}

config :core, :mongo_audit_log,
  url: {:system, :string, "AUDIT_LOG_DB_URL"},
  pool_size: {:system, :integer, "AUDIT_LOG_DB_POOL_SIZE", 10}

config :kaffe,
  producer: [
    endpoints: {:system, :string, "KAFKA_BROKERS"},
    topics: ["medical_events", "mongo_events"]
  ]
