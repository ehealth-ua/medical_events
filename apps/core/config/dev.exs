use Mix.Config

config :core, Core.Patients, pk_hash_salt: "aNg9JXF48uQrIjFYSGXDmKEYBXuu0BOEbkecHq7uV9qmzOT1dvxoueZlsA022ahc3GgFfFHd"

config :core, :mongo, url: "mongodb://localhost:27017/medical_data"
config :core, :mongo_audit_log, url: "mongodb://localhost:27017/medical_data"
