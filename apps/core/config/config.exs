# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# You can configure your application as:
#
#     config :core, key: :value
#
# and access this configuration in your application as:
#
#     Application.get_env(:core, :key)
#
# You can also configure a 3rd-party app:
#
#     config :logger, level: :info
#

config :core,
  microservices: [
    il: Core.Microservices.Il,
    digital_signature: Core.Microservices.DigitalSignature,
    casher: Core.Microservices.Casher,
    media_storage: Core.Microservices.MediaStorage
  ],
  cache: [
    validators: Core.Validators.Cache
  ],
  kafka: [
    producer: Core.Kafka.Producer
  ]

config :core, Core.Microservices.Il,
  endpoint: {:system, "IL_ENDPOINT", "http://api-svc.il"},
  hackney_options: [
    connect_timeout: 30_000,
    recv_timeout: 30_000,
    timeout: 30_000
  ]

config :core, Core.Microservices.MediaStorage,
  endpoint: {:system, "MEDIA_STORAGE_ENDPOINT", "http://api-svc.ael"},
  encounter_bucket: {:system, "MEDIA_STORAGE_ENCOUNTER_BUCKET", "encounters-dev"},
  enabled?: {:system, :boolean, "MEDIA_STORAGE_ENABLED", false},
  hackney_options: [
    connect_timeout: {:system, :integer, "MEDIA_STORAGE_REQUEST_TIMEOUT", 30_000},
    recv_timeout: {:system, :integer, "MEDIA_STORAGE_REQUEST_TIMEOUT", 30_000},
    timeout: {:system, :integer, "MEDIA_STORAGE_REQUEST_TIMEOUT", 30_000}
  ]

config :core, Core.Microservices.DigitalSignature,
  endpoint: {:system, "DIGITAL_SIGNATURE_ENDPOINT", "http://api-svc.digital-signature"},
  hackney_options: [
    connect_timeout: 30_000,
    recv_timeout: 30_000,
    timeout: 30_000
  ]

config :core, Core.Microservices.Casher,
  endpoint: {:system, "CASHER_ENDPOINT", "http://casher-svc.il"},
  hackney_options: [
    connect_timeout: 30_000,
    recv_timeout: 30_000,
    timeout: 30_000
  ]

config :core, Core.Patients, pk_hash_salt: {:system, "PERSON_PK_HASH_SALT"}

config :core, Core.Redis,
  host: {:system, "REDIS_HOST", "0.0.0.0"},
  port: {:system, :integer, "REDIS_PORT", 6379},
  password: {:system, "REDIS_PASSWORD", nil},
  database: {:system, "REDIS_DATABASE", nil},
  pool_size: {:system, :integer, "REDIS_POOL_SIZE", 5}

config :vex,
  sources: [
    [
      datetime: Core.Validators.DateTime,
      date: Core.Validators.Date,
      reference: Core.Validators.Reference,
      value: Core.Validators.Value,
      division: Core.Validators.Division,
      employee: Core.Validators.Employee,
      legal_entity: Core.Validators.LegalEntity,
      diagnoses_role: Core.Validators.DiagnosesRole,
      visit_context: Core.Validators.VisitContext,
      episode_context: Core.Validators.EpisodeContext,
      diagnosis_condition: Core.Validators.DiagnosisCondition,
      strict_presence: Core.Validators.StrictPresence,
      observation_reference: Core.Validators.ObservationReference,
      source: Core.Validators.Source,
      unique_ids: Core.Validators.UniqueIds,
      mongo_uuid: Core.Validators.MongoUUID,
      dictionary_reference: Core.Validators.DictionaryReference
    ],
    Vex.Validators
  ]

config :core, Core.Validators.JsonSchema, errors_limit: {:system, :integer, "JSON_SCHEMA_ERRORS_LIMIT", 6}

config :kafka_ex,
  # A list of brokers to connect to. This can be in either of the following formats
  #
  #  * [{"HOST", port}...]
  #  * CSV - `"HOST:PORT,HOST:PORT[,...]"`
  #
  # If you receive :leader_not_available
  # errors when producing messages, it may be necessary to modify "advertised.host.name" in the
  # server.properties file.
  # In the case below you would set "advertised.host.name=localhost"
  brokers: "localhost:9092",
  #
  # the default consumer group for worker processes, must be a binary (string)
  #    NOTE if you are on Kafka < 0.8.2 or if you want to disable the use of
  #    consumer groups, set this to :no_consumer_group (this is the
  #    only exception to the requirement that this value be a binary)
  consumer_group: "medical_events",
  # Set this value to true if you do not want the default
  # `KafkaEx.Server` worker to start during application start-up -
  # i.e., if you want to start your own set of named workers
  disable_default_worker: false,
  # Timeout value, in msec, for synchronous operations (e.g., network calls).
  # If this value is greater than GenServer's default timeout of 5000, it will also
  # be used as the timeout for work dispatched via KafkaEx.Server.call (e.g., KafkaEx.metadata).
  # In those cases, it should be considered a 'total timeout', encompassing both network calls and
  # wait time for the genservers.
  sync_timeout: 3000,
  # Supervision max_restarts - the maximum amount of restarts allowed in a time frame
  max_restarts: 10,
  # Supervision max_seconds -  the time frame in which :max_restarts applies
  max_seconds: 60,
  # Interval in milliseconds that GenConsumer waits to commit offsets.
  commit_interval: 5_000,
  # Threshold number of messages consumed for GenConsumer to commit offsets
  # to the broker.
  auto_offset_reset: :earliest,
  commit_threshold: 100,
  # This is the flag that enables use of ssl
  # use_ssl: true,
  # see SSL OPTION DESCRIPTIONS - CLIENT SIDE at http://erlang.org/doc/man/ssl.html
  # for supported options
  # ssl_options: [
  #   cacertfile: System.cwd <> "/ssl/ca-cert",
  #   certfile: System.cwd <> "/ssl/cert.pem",
  #   keyfile: System.cwd <> "/ssl/key.pem",
  # ],
  # set this to the version of the kafka broker that you are using
  # include only major.minor.patch versions.  must be at least 0.8.0
  kafka_version: "1.1.0"

config :core, :encounter_package,
  encounter_max_days_passed: {:system, :integer, "ENCOUNTER_MAX_DAYS_PASSED", 7},
  condition_max_days_passed: {:system, :integer, "CONDITION_MAX_DAYS_PASSED", 150 * 365},
  observation_max_days_passed: {:system, :integer, "OBSERVATION_MAX_DAYS_PASSED", 150 * 365},
  allergy_intolerance_max_days_passed: {:system, :integer, "ALLERGY_INTOLERANCE_MAX_DAYS_PASSED", 150 * 365},
  immunization_max_days_passed: {:system, :integer, "IMMUNIZATION_MAX_DAYS_PASSED", 150 * 365}

config :core, digital_signarure_enabled?: {:system, :boolean, "DIGITAL_SIGNATURE_ENABLED", true}

import_config "#{Mix.env()}.exs"
