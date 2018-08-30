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
        with {:ok, response, status_code} <- Patients.consume_create_package(package_create_job) do
          {:ok, %{matched_count: 1, modified_count: 1}} = Jobs.update(id, Job.status(:processed), response, status_code)
          :ok
        end

      _ ->
        response = "Can't get request by id #{id}"
        Logger.warn(fn -> response end)
        :ok
    end
  end

  def consume(%EpisodeCreateJob{_id: id} = episode_create_job) do
    case Jobs.get_by_id(id) do
      {:ok, _job} ->
        with {:ok, response, status_code} <- Patients.consume_create_episode(episode_create_job) do
          {:ok, %{matched_count: 1, modified_count: 1}} = Jobs.update(id, Job.status(:processed), response, status_code)
          :ok
        end

      _ ->
        response = "Can't get request by id #{id}"
        Logger.warn(fn -> response end)
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
