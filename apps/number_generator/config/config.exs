# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :number_generator, NumberGenerator.Generator, key: {:system, "NUMBER_GENERATOR_KEY", "random"}

config :number_generator,
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
