defmodule Core.Kafka.Consumer do
  @moduledoc false

  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.EpisodeCancelJob
  alias Core.Jobs.EpisodeCloseJob
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Jobs.EpisodeUpdateJob
  alias Core.Jobs.PackageCancelJob
  alias Core.Jobs.PackageCreateJob
  alias Core.Patients
  require Logger

  def consume(%PackageCreateJob{} = package_create_job) do
    do_consume(Patients, :consume_create_package, package_create_job)
  end

  def consume(%PackageCancelJob{} = package_cancel_job) do
    do_consume(Patients, :consume_cancel_package, package_cancel_job)
  end

  def consume(%EpisodeCreateJob{} = episode_create_job) do
    do_consume(Patients, :consume_create_episode, episode_create_job)
  end

  def consume(%EpisodeUpdateJob{} = episode_update_job) do
    do_consume(Patients, :consume_update_episode, episode_update_job)
  end

  def consume(%EpisodeCloseJob{} = episode_close_job) do
    do_consume(Patients, :consume_close_episode, episode_close_job)
  end

  def consume(%EpisodeCancelJob{} = episode_cancel_job) do
    do_consume(Patients, :consume_cancel_episode, episode_cancel_job)
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
          with {:ok, response, status_code} <- apply(module, fun, [kafka_job]) do
            {:ok, %{matched_count: 1, modified_count: 1}} =
              Jobs.update(id, Job.status(:processed), response, status_code)
          else
            {:error, response, status_code} ->
              {:ok, %{matched_count: 1, modified_count: 1}} =
                Jobs.update(id, Job.status(:failed), response, status_code)
          end
        rescue
          error ->
            Jobs.update(id, Job.status(:failed_with_error), inspect(error), 500)
            Logger.warn(inspect(error) <> ". Job: " <> inspect(kafka_job))
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
