use Mix.Config

# Configuration for production environment.
# It should read environment variables to follow 12 factor apps convention.

# Configure your database
config :core, Core.Repo,
  adapter: Mongo.Ecto,
  database: "${DB_NAME}",
  username: "${DB_USER}",
  password: "${DB_PASSWORD}",
  hostname: "${DB_HOST}",
  port: "${DB_PORT}",
  pool_size: "${DB_POOL_SIZE}",
  timeout: 15_000,
  pool_timeout: 15_000,
  loggers: [{Ecto.LoggerJSON, :log, [:info]}]
