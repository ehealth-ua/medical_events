use Mix.Config

# Configuration for test environment
config :ex_unit, capture_log: false

# Configure your database
config :core, Core.Repo,
  adapter: Mongo.Ecto,
  database: "medical_data_test",
  hostname: "localhost",
  ownership_timeout: 120_000_000,
  loggers: [{Ecto.LoggerJSON, :log, [:info]}]
