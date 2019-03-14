use Mix.Config

config :medical_events_scheduler, MedicalEventsScheduler.Worker,
  service_request_autoexpiration_schedule: {:system, :string, "SERVICE_REQUEST_AUTOEXPIRATION_SCHEDULE", "*/30 * * * *"}

config :medical_events_scheduler,
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
