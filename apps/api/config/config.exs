# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :api, namespace: Api

config :phoenix, :json_library, Jason

# Configures the endpoint
config :api, ApiWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "ihMJQLMR8bqvos75NHg26kHyXVlsfJ+OQpS+zl+ElGtHPQOxMXd28ZQsvZoR5xvd",
  render_errors: [
    view: EView.Views.PhoenixError,
    accepts: ~w(json)
  ],
  instrumenters: [LoggerJSON.Phoenix.Instruments]

config :phoenix, :format_encoders, json: Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
config :api, env: Mix.env()

config :api,
  topologies: [
    k8s_transactions: [
      strategy: Elixir.Cluster.Strategy.Kubernetes,
      config: [
        mode: :dns,
        kubernetes_node_basename: "me_transactions",
        kubernetes_selector: "app=me-transactions",
        kubernetes_namespace: "me",
        polling_interval: 10_000
      ]
    ]
  ]

import_config "#{Mix.env()}.exs"
