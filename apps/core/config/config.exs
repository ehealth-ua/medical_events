# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :core,
  microservices: [
    media_storage: Core.Microservices.MediaStorage
  ],
  cache: [
    validators: Core.Validators.Cache
  ],
  kafka: [
    producer: Core.Kafka.Producer
  ],
  rpc_worker: Core.Rpc.Worker,
  system_user: {:system, "EHEALTH_SYSTEM_USER", "4261eacf-8008-4e62-899f-de1e2f7065f0"}

config :core, env: Mix.env()

config :logger_json, :backend,
  formatter: EhealthLogger.Formatter,
  metadata: :all

config :logger,
  backends: [LoggerJSON],
  level: :info

config :core,
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
    ],
    k8s_ehealth: [
      strategy: Elixir.Cluster.Strategy.Kubernetes,
      config: [
        mode: :dns,
        kubernetes_node_basename: "ehealth",
        kubernetes_selector: "app=api",
        kubernetes_namespace: "il",
        polling_interval: 10_000
      ]
    ],
    k8s_number_generator: [
      strategy: Elixir.Cluster.Strategy.Kubernetes,
      config: [
        mode: :dns,
        kubernetes_node_basename: "number_generator",
        kubernetes_selector: "app=number-generator",
        kubernetes_namespace: "me",
        polling_interval: 10_000
      ]
    ],
    k8s_mpi: [
      strategy: Elixir.Cluster.Strategy.Kubernetes,
      config: [
        mode: :dns,
        kubernetes_node_basename: "mpi",
        kubernetes_selector: "app=api",
        kubernetes_namespace: "mpi",
        polling_interval: 10_000
      ]
    ],
    k8s_ops: [
      strategy: Elixir.Cluster.Strategy.Kubernetes,
      config: [
        mode: :dns,
        kubernetes_node_basename: "ops",
        kubernetes_selector: "app=api",
        kubernetes_namespace: "ops",
        polling_interval: 10_000
      ]
    ]
  ]

config :core, Core.Microservices.MediaStorage,
  encounter_bucket: {:system, "MEDIA_STORAGE_ENCOUNTER_BUCKET", "encounters-dev"},
  service_request_bucket: {:system, "MEDIA_STORAGE_SERVICE_REQUEST_BUCKET", "service-requests-dev"},
  diagnostic_report_bucket: {:system, "MEDIA_STORAGE_DIAGNOSTIC_REPORT_BUCKET", "diagnostic-reports-dev"},
  enabled?: {:system, :boolean, "MEDIA_STORAGE_ENABLED", false},
  hackney_options: [
    connect_timeout: {:system, :integer, "MEDIA_STORAGE_REQUEST_TIMEOUT", 30_000},
    recv_timeout: {:system, :integer, "MEDIA_STORAGE_REQUEST_TIMEOUT", 30_000},
    timeout: {:system, :integer, "MEDIA_STORAGE_REQUEST_TIMEOUT", 30_000}
  ]

config :core, Core.DigitalSignature, enabled: {:system, :boolean, "DIGITAL_SIGNATURE_ENABLED", true}

config :core, Core.Encryptor,
  keyphrase: {:system, :string, "PERSON_PK_KEYPHRASE"},
  ivphrase: {:system, :string, "PERSON_PK_IVPHRASE"}

config :core, Core.Redis,
  host: {:system, "REDIS_HOST", "0.0.0.0"},
  port: {:system, :integer, "REDIS_PORT", 6379},
  password: {:system, "REDIS_PASSWORD", nil},
  database: {:system, "REDIS_DATABASE", nil},
  pool_size: {:system, :integer, "REDIS_POOL_SIZE", 5}

config :core, Core.Validators.JsonSchema, errors_limit: {:system, :integer, "JSON_SCHEMA_ERRORS_LIMIT", 6}

config :core, Core.Rpc.Worker,
  max_attempts: {:system, :integer, "RPC_MAX_ATTEMPTS", 3},
  timeout: {:system, :integer, "RPC_TIMEOUT", 5000},
  ergonodes: [%{"basename" => "me_transactions", "process" => :mongo_transaction, "pid_message" => :pid}]

config :kaffe,
  producer: [
    endpoints: [localhost: 9092],
    topics: ["medical_events", "mongo_events"]
  ]

config :core, Core.ServiceRequests.Consumer,
  cancel_sms: {:system, :string, "CANCEL_SMS", "Ваше направлення під номером <%= @number %> було відмінено"},
  recall_sms: {:system, :string, "RECALL_SMS", "Ваше направлення під номером <%= @number %> було відкликано"},
  service_request_expiration_days: {:system, :integer, "SERVICE_REQUEST_EXPIRATION_DAYS", 7}

config :core, :encounter_package,
  encounter_max_days_passed: {:system, :integer, "ENCOUNTER_MAX_DAYS_PASSED", 7},
  condition_max_days_passed: {:system, :integer, "CONDITION_MAX_DAYS_PASSED", 150 * 365},
  observation_max_days_passed: {:system, :integer, "OBSERVATION_MAX_DAYS_PASSED", 150 * 365},
  risk_assessment_max_days_passed: {:system, :integer, "RISK_ASSESSMENT_MAX_DAYS_PASSED", 150 * 365},
  allergy_intolerance_max_days_passed: {:system, :integer, "ALLERGY_INTOLERANCE_MAX_DAYS_PASSED", 150 * 365},
  immunization_max_days_passed: {:system, :integer, "IMMUNIZATION_MAX_DAYS_PASSED", 150 * 365},
  device_max_days_passed: {:system, :integer, "DEVICE_MAX_DAYS_PASSED", 150 * 365},
  medication_statement_max_days_passed: {:system, :integer, "MEDICATION_STATEMENT_MAX_DAYS_PASSED", 150 * 365},
  diagnostic_report_max_days_passed: {:system, :integer, "DIAGNOSTIC_REPORT_MAX_DAYS_PASSED", 150 * 365},
  use_encounter_package_short_schema: {:system, :boolean, "USE_ENCOUNTER_PACKAGE_SHORT_SCHEMA", false}

config :core, :summary,
  conditions_whitelist: {:system, :list, "SUMMARY_CONDITIONS_ALLOWED", ["R80"]},
  observations_whitelist: {:system, :list, "SUMMARY_OBSERVATIONS_ALLOWED", ["8310-5", "8462-4", "8480-6", "80319-7"]},
  diagnostic_reports_whitelist: {:system, :list, "SUMMARY_DIAGNOSTIC_REPORTS_ALLOWED", []}

config :core, :approval, expire_in_minutes: {:system, :integer, "APPROVAL_EXPIRATION", 60 * 24}

import_config "#{Mix.env()}.exs"
