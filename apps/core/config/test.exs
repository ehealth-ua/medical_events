use Mix.Config

# Configuration for test environment
config :ex_unit, capture_log: false

config :core,
  microservices: [
    il: IlMock,
    digital_signature: DigitalSignatureMock
  ],
  cache: [
    validators: Core.Validators.CacheTest
  ]

config :core, :mongo, url: "mongodb://localhost:27017/medical_data_test"
