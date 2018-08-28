defmodule Core.Kafka.Consumer do
  @moduledoc false

  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Jobs.PackageCreateJob
  alias Core.Patients
  require Logger

  @doc """
  TODO: add digital signature error handling
  """
  def consume(%PackageCreateJob{_id: id} = package_create_job) do
    case Jobs.get_by_id(id) do
      {:ok, _job} ->
        with {:ok, response} <- Patients.consume_create_package(package_create_job) do
          Jobs.update(id, Job.status(:processed), response, 200)
          :ok
        end

      _ ->
        response = "Can't get request by id #{id}"
        Logger.warn(fn -> response end)
        Jobs.update(id, Job.status(:failed), response, 404)
        :ok
    end
  end

  def consume(%EpisodeCreateJob{_id: id} = episode_create_job) do
    case Jobs.get_by_id(id) do
      {:ok, _job} ->
        with {:ok, response} <- Patients.consume_create_episode(episode_create_job) do
          Jobs.update(id, Job.status(:processed), response, 200)
          :ok
        end

      _ ->
        response = "Can't get request by id #{id}"
        Logger.warn(fn -> response end)
        Jobs.update(id, Job.status(:failed), response, 404)
        :ok
    end
  end

  def consume(value) do
    Logger.warn(fn ->
      "unknown kafka event #{inspect(value)}"
    end)

    :ok
  end
end
