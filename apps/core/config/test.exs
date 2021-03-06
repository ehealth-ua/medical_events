use Mix.Config

# Configuration for test environment
config :ex_unit, capture_log: true

config :logger, level: :warn

config :core,
  microservices: [
    media_storage: MediaStorageMock
  ],
  cache: [
    validators: Core.Validators.CacheTest
  ],
  kafka: [
    producer: KafkaMock
  ],
  rpc_worker: WorkerMock

config :core, Core.Encryptor,
  keyphrase: "8grv872gt3trc92b",
  ivphrase: "99yBSYB*Y99yr932"

config :core, :mongo,
  url: "mongodb://localhost:27017/medical_data_test",
  pool_size: 10

config :core, :summary, diagnostic_reports_whitelist: {:system, :list, "SUMMARY_DIAGNOSTIC_REPORTS_ALLOWED", ["109006"]}
