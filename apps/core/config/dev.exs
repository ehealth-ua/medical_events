use Mix.Config

# Configuration for test environment

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with brunch.io to recompile .js and .css sources.
# Configure your database

config :core, Core.Repo,
  adapter: Mongo.Ecto,
  database: "medical_data",
  hostname: "localhost",
  pool_size: 10
