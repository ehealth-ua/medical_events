use Mix.Config

# Configuration for test environment
config :ex_unit, capture_log: true

config :core,
  microservices: [
    il: IlMock,
    digital_signature: DigitalSignatureMock,
    casher: CasherMock,
    media_storage: MediaStorageMock
  ],
  cache: [
    validators: Core.Validators.CacheTest
  ],
  kafka: [
    producer: KafkaMock
  ],
  rpc_worker: WorkerMock

config :core, Core.Patients.Encryptor,
  keyphrase: "8grv872gt3trc92b",
  ivphrase: "99yBSYB*Y99yr932"

config :core, :mongo, url: "mongodb://localhost:27017/medical_data_test"
config :core, :mongo_audit_log, url: "mongodb://localhost:27017/medical_events_audit_log"
