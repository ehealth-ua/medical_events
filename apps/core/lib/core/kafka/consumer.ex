defmodule Core.Kafka.Consumer do
  @moduledoc false

  alias Core.Approvals
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.ApprovalCreateJob
  alias Core.Jobs.ApprovalResendJob
  alias Core.Jobs.EpisodeCancelJob
  alias Core.Jobs.EpisodeCloseJob
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Jobs.EpisodeUpdateJob
  alias Core.Jobs.PackageCancelJob
  alias Core.Jobs.PackageCreateJob
  alias Core.Jobs.ServiceRequestCreateJob
  alias Core.Jobs.ServiceRequestReleaseJob
  alias Core.Jobs.ServiceRequestUseJob
  alias Core.Patients
  alias Core.Patients.Episodes.Consumer, as: EpisodesConsumer
  alias Core.ServiceRequests

  require Logger

  def consume(%PackageCreateJob{} = package_create_job) do
    do_consume(Patients, :consume_create_package, package_create_job)
  end

  def consume(%PackageCancelJob{} = package_cancel_job) do
    do_consume(Patients, :consume_cancel_package, package_cancel_job)
  end

  def consume(%EpisodeCreateJob{} = episode_create_job) do
    do_consume(EpisodesConsumer, :consume_create_episode, episode_create_job)
  end

  def consume(%EpisodeUpdateJob{} = episode_update_job) do
    do_consume(EpisodesConsumer, :consume_update_episode, episode_update_job)
  end

  def consume(%EpisodeCloseJob{} = episode_close_job) do
    do_consume(EpisodesConsumer, :consume_close_episode, episode_close_job)
  end

  def consume(%EpisodeCancelJob{} = episode_cancel_job) do
    do_consume(EpisodesConsumer, :consume_cancel_episode, episode_cancel_job)
  end

  def consume(%ServiceRequestCreateJob{} = service_request_create_job) do
    do_consume(ServiceRequests, :consume_create_service_request, service_request_create_job)
  end

  def consume(%ServiceRequestUseJob{} = service_request_use_job) do
    do_consume(ServiceRequests, :consume_use_service_request, service_request_use_job)
  end

  def consume(%ServiceRequestReleaseJob{} = service_request_release_job) do
    do_consume(ServiceRequests, :consume_release_service_request, service_request_release_job)
  end

  def consume(%ApprovalCreateJob{} = approval_create_job) do
    do_consume(Approvals, :consume_create_approval, approval_create_job)
  end

  def consume(%ApprovalResendJob{} = approval_resend_job) do
    do_consume(Approvals, :consume_resend_approval, approval_resend_job)
  end

  def consume(value) do
    Logger.warn(fn ->
      "unknown kafka event #{inspect(value)}"
    end)

    :ok
  end

  defp do_consume(module, fun, %{_id: id} = kafka_job) do
    case Jobs.get_by_id(id) do
      {:ok, _} ->
        :ets.new(:message_cache, [:set, :protected, :named_table])

        try do
          apply(module, fun, [kafka_job])
        rescue
          error ->
            Jobs.update(id, Job.status(:failed_with_error), inspect(error), 500)
            Logger.warn(inspect(error) <> ". Job: " <> inspect(kafka_job) <> "Stacktrace: " <> inspect(__STACKTRACE__))
        end

        :ets.delete(:message_cache)
        :ok

      _ ->
        response = "Can't get request by id #{id}"
        Logger.warn(fn -> response end)
        :ok
    end
  end
end
