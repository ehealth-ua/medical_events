# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :event_consumer, env: Mix.env()

config :event_consumer,
  topologies: [
    k8s_ehealth: [
      strategy: Elixir.Cluster.Strategy.Kubernetes,
      config: [
        mode: :dns,
        kubernetes_node_basename: "ehealth",
        kubernetes_selector: "app=api",
        kubernetes_namespace: "il",
        polling_interval: 10_000
      ]
    ]
  ]

config :kaffe,
  consumer: [
    endpoints: [localhost: 9092],
    topics: ["medical_events"],
    consumer_group: "medical_event_group",
    message_handler: EventConsumer.Kafka.MedicalEventConsumer
  ]

import_config "#{Mix.env()}.exs"
