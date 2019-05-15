# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :core,
  microservices: [
    il: Core.Microservices.Il,
    digital_signature: Core.Microservices.DigitalSignature,
    media_storage: Core.Microservices.MediaStorage,
    otp_verification: Core.Microservices.OTPVerification
  ],
  cache: [
    validators: Core.Validators.Cache
  ],
  kafka: [
    producer: Core.Kafka.Producer
  ],
  rpc_worker: Core.Rpc.Worker,
  system_user: {:system, "EHEALTH_SYSTEM_USER", "4261eacf-8008-4e62-899f-de1e2f7065f0"}

config :logger_json, :backend,
  formatter: EhealthLogger.Formatter,
  metadata: :all

config :logger,
  backends: [LoggerJSON],
  level: :info

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
  service_request_bucket: {:system, "MEDIA_STORAGE_SERVICE_REQUEST_BUCKET", "service-requests-dev"},
  diagnostic_report_bucket: {:system, "MEDIA_STORAGE_DIAGNOSTIC_REPORT_BUCKET", "diagnostic-reports-dev"},
  enabled?: {:system, :boolean, "MEDIA_STORAGE_ENABLED", false},
  hackney_options: [
    connect_timeout: {:system, :integer, "MEDIA_STORAGE_REQUEST_TIMEOUT", 30_000},
    recv_timeout: {:system, :integer, "MEDIA_STORAGE_REQUEST_TIMEOUT", 30_000},
    timeout: {:system, :integer, "MEDIA_STORAGE_REQUEST_TIMEOUT", 30_000}
  ]

config :core, Core.Microservices.DigitalSignature,
  enabled: {:system, :boolean, "DIGITAL_SIGNATURE_ENABLED", true},
  endpoint: {:system, "DIGITAL_SIGNATURE_ENDPOINT", "http://api-svc.digital-signature"},
  hackney_options: [
    connect_timeout: 30_000,
    recv_timeout: 30_000,
    timeout: 30_000
  ]

config :core, Core.Microservices.OTPVerification,
  endpoint: {:system, "OTP_VERIFICATION_ENDPOINT", "http://api-svc.verification"},
  hackney_options: [
    connect_timeout: 30_000,
    recv_timeout: 30_000,
    timeout: 30_000
  ]

config :core, Core.Encryptor,
  keyphrase: {:system, :string, "PERSON_PK_KEYPHRASE"},
  ivphrase: {:system, :string, "PERSON_PK_IVPHRASE"}

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
      diagnosis_condition: Core.Validators.DiagnosisCondition,
      strict_presence: Core.Validators.StrictPresence,
      observation_context: Core.Validators.ObservationContext,
      observation_reference: Core.Validators.ObservationReference,
      source: Core.Validators.Source,
      unique_ids: Core.Validators.UniqueIds,
      mongo_uuid: Core.Validators.MongoUUID,
      dictionary_reference: Core.Validators.DictionaryReference,
      drfo: Core.Validators.Drfo,
      encounter_reference: Core.Validators.EncounterReference,
      episode_reference: Core.Validators.EpisodeReference,
      condition_reference: Core.Validators.ConditionReference,
      condition_context: Core.Validators.ConditionContext,
      diagnoses_code: Core.Validators.DiagnosesCode,
      service_request_reference: Core.Validators.ServiceRequestReference,
      max_days_passed: Core.Validators.MaxDaysPassed,
      approval_granted_to_reference: Core.Validators.ApprovalGrantedToReference,
      medication_request_reference: Core.Validators.MedicationRequestReference,
      diagnostic_report_reference: Core.Validators.DiagnosticReportReference,
      diagnostic_report_context: Core.Validators.DiagnosticReportContext,
      service_reference: Core.Validators.ServiceReference,
      service_group_reference: Core.Validators.ServiceGroupReference
    ],
    Vex.Validators
  ]

config :core, Core.Validators.JsonSchema, errors_limit: {:system, :integer, "JSON_SCHEMA_ERRORS_LIMIT", 6}

config :core, Core.Rpc.Worker,
  max_attempts: {:system, :integer, "RPC_MAX_ATTEMPTS", 3},
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
