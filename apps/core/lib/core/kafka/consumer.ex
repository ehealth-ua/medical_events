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
  alias Core.Jobs.PackageSaveConditionsJob
  alias Core.Jobs.PackageSaveObservationsJob
  alias Core.Jobs.PackageSavePatientJob
  alias Core.Kafka.Producer
  alias Core.Microservices.Error
  alias Core.Patients
  alias Core.Patients.Package

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

  def consume(%PackageSavePatientJob{} = package_save_patient_job) do
    do_consume(Package, :consume_save_patient, package_save_patient_job)
  end

  def consume(%PackageSaveConditionsJob{} = package_save_conditions_job) do
    do_consume(Package, :consume_save_conditions, package_save_conditions_job)
  end

  def consume(%PackageSaveObservationsJob{} = package_save_observations_job) do
    do_consume(Package, :consume_save_observations, package_save_observations_job)
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
          case apply(module, fun, [kafka_job]) do
            {:ok, response, status_code} ->
              {:ok, %{matched_count: 1, modified_count: 1}} =
                Jobs.update(id, Job.status(:processed), response, status_code)

            :ok ->
              :ok

            {:error, response, status_code} ->
              {:ok, %{matched_count: 1, modified_count: 1}} =
                Jobs.update(id, Job.status(:failed), response, status_code)
          end
        rescue
          # Add message to the end of log for further processing
          error in Error ->
            Logger.warn(inspect(error) <> ". Job: " <> inspect(kafka_job))
            Producer.publish_medical_event(kafka_job)

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
