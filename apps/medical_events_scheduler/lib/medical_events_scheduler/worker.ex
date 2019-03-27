defmodule MedicalEventsScheduler.Worker do
  @moduledoc false

  use Quantum.Scheduler, otp_app: :medical_events_scheduler

  alias Crontab.CronExpression.Parser
  alias MedicalEventsScheduler.Jobs.ApprovalsCleanup
  alias MedicalEventsScheduler.Jobs.JobsCleanup
  alias MedicalEventsScheduler.Jobs.ServiceRequestsAutoexpiration
  alias Quantum.Job
  alias Quantum.RunStrategy.Local

  def create_jobs do
    create_job(&ServiceRequestsAutoexpiration.run/0, :service_requests_autoexpiration_schedule)
    create_job(&ApprovalsCleanup.run/0, :approvals_cleanup_schedule)
    create_job(&JobsCleanup.run/0, :jobs_cleanup_schedule)
  end

  defp create_job(fun, config_name) do
    config = Confex.fetch_env!(:medical_events_scheduler, __MODULE__)

    __MODULE__.new_job()
    |> Job.set_name(config_name)
    |> Job.set_overlap(false)
    |> Job.set_schedule(Parser.parse!(config[config_name]))
    |> Job.set_task(fun)
    |> Job.set_run_strategy(%Local{})
    |> __MODULE__.add_job()
  end
end
