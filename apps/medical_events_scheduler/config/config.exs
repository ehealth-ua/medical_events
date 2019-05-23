use Mix.Config

config :medical_events_scheduler, env: Mix.env()

config :medical_events_scheduler, MedicalEventsScheduler.Worker,
  service_requests_autoexpiration_schedule:
    {:system, :string, "SERVICE_REQUESTS_AUTOEXPIRATION_SCHEDULE", "0 0,4 * * *"},
  approvals_cleanup_schedule: {:system, :string, "APPROVALS_CLEANUP_SCHEDULE", "20 0 * * *"},
  jobs_cleanup_schedule: {:system, :string, "JOBS_CLEANUP_SCHEDULE", "40 0 * * *"}

config :medical_events_scheduler, MedicalEventsScheduler.Jobs.ApprovalsCleanup,
  approval_ttl_hours: {:system, :integer, "APPROVAL_TTL_HOURS", 12}

config :medical_events_scheduler, MedicalEventsScheduler.Jobs.JobsCleanup,
  job_ttl_days: {:system, :integer, "JOB_TTL_DAYS", 7}

config :swarm, node_blacklist: [~r/^.+$/]

import_config "#{Mix.env()}.exs"
