defmodule Core.Patients.Episodes.Producer do
  @moduledoc false

  alias Core.Jobs
  alias Core.Jobs.EpisodeCancelJob
  alias Core.Jobs.EpisodeCloseJob
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Jobs.EpisodeUpdateJob
  alias Core.Patients
  alias Core.Patients.Episodes
  alias Core.Patients.Validators
  alias Core.Validators.JsonSchema

  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  def produce_create_episode(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash, projection: [status: true]),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:episode_create, Map.drop(params, ~w(patient_id patient_id_hash))),
         {:ok, job, episode_create_job} <-
           Jobs.create(
             user_id,
             patient_id_hash,
             EpisodeCreateJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(episode_create_job) do
      {:ok, job}
    end
  end

  def produce_update_episode(
        %{"patient_id_hash" => patient_id_hash, "id" => id} = url_params,
        request_params,
        conn_params
      ) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash, projection: [status: true]),
         :ok <- Validators.is_active(patient),
         {:ok, _} <- Episodes.get_by_id(patient_id_hash, id),
         :ok <- JsonSchema.validate(:episode_update, request_params),
         {:ok, job, episode_update_job} <-
           Jobs.create(
             conn_params["user_id"],
             patient_id_hash,
             EpisodeUpdateJob,
             url_params |> Map.merge(conn_params) |> Map.put("request_params", request_params)
           ),
         :ok <- @kafka_producer.publish_medical_event(episode_update_job) do
      {:ok, job}
    end
  end

  def produce_close_episode(
        %{"patient_id_hash" => patient_id_hash, "id" => id} = url_params,
        request_params,
        conn_params
      ) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash, projection: [status: true]),
         :ok <- Validators.is_active(patient),
         {:ok, _} <- Episodes.get_by_id(patient_id_hash, id),
         :ok <- JsonSchema.validate(:episode_close, request_params),
         {:ok, job, episode_close_job} <-
           Jobs.create(
             conn_params["user_id"],
             patient_id_hash,
             EpisodeCloseJob,
             url_params |> Map.merge(conn_params) |> Map.put("request_params", request_params)
           ),
         :ok <- @kafka_producer.publish_medical_event(episode_close_job) do
      {:ok, job}
    end
  end

  def produce_cancel_episode(
        %{"patient_id_hash" => patient_id_hash, "id" => id} = url_params,
        request_params,
        conn_params
      ) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash, projection: [status: true]),
         :ok <- Validators.is_active(patient),
         {:ok, _} <- Episodes.get_by_id(patient_id_hash, id),
         :ok <- JsonSchema.validate(:episode_cancel, request_params),
         {:ok, job, episode_cancel_job} <-
           Jobs.create(
             conn_params["user_id"],
             patient_id_hash,
             EpisodeCancelJob,
             url_params |> Map.merge(conn_params) |> Map.put("request_params", request_params)
           ),
         :ok <- @kafka_producer.publish_medical_event(episode_cancel_job) do
      {:ok, job}
    end
  end
end
