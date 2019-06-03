defmodule Core.ServiceRequests do
  @moduledoc false

  use Confex, otp_app: :core

  alias Core.Encryptor
  alias Core.Episode
  alias Core.Mongo
  alias Core.Paging
  alias Core.Patients
  alias Core.Patients.Encounters
  alias Core.Patients.Episodes
  alias Core.Patients.Validators
  alias Core.Search
  alias Core.ServiceRequest
  alias Core.Validators.JsonSchema
  alias Scrivener.Page
  require Logger

  @collection ServiceRequest.collection()

  defp check_patient(%{"patient_id_hash" => patient_id_hash}) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash, projection: [status: true]) do
      Validators.is_active(patient)
    end
  end

  defp check_patient(_), do: :ok

  defp check_episode(%{"patient_id_hash" => patient_id_hash, "episode_id" => episode_id}) do
    with {:ok, %Episode{}} <- Episodes.get_by_id(patient_id_hash, episode_id), do: :ok
  end

  defp check_episode(_), do: :ok

  defp get_encounter_ids(%{"patient_id_hash" => patient_id_hash, "episode_id" => episode_id}) do
    patient_id_hash
    |> Encounters.get_episode_encounters(Mongo.string_to_uuid(episode_id))
    |> Enum.map(& &1["encounter_id"])
    |> Enum.uniq()
  end

  defp get_encounter_ids(_), do: nil

  def list(params, schema) do
    search_params = Map.drop(params, ~w(page page_size))
    paging_params = Map.take(params, ~w(page page_size))

    with :ok <- JsonSchema.validate(schema, search_params),
         :ok <- check_patient(params),
         :ok <- check_episode(params),
         encounter_ids <- get_encounter_ids(params),
         [_ | _] = pipeline <- service_requests_search_pipe(search_params, encounter_ids),
         %Page{entries: service_requests} = page <-
           Paging.paginate(
             :aggregate,
             @collection,
             pipeline,
             paging_params
           ) do
      {:ok, %Page{page | entries: Enum.map(service_requests, &ServiceRequest.create/1)}}
    else
      nil -> nil
      {:error, error} -> {:error, error}
      _ -> {:ok, Paging.create()}
    end
  end

  defp service_requests_search_pipe(params, encounters) do
    requester_legal_entity =
      if params["requester_legal_entity"], do: Mongo.string_to_uuid(params["requester_legal_entity"])

    used_by_legal_entity = if params["used_by_legal_entity"], do: Mongo.string_to_uuid(params["used_by_legal_entity"])
    code = if params["code"], do: Mongo.string_to_uuid(params["code"])

    %{"$match" => %{}}
    |> Search.add_param(Encryptor.encrypt(params["requisition"]), ["$match", "requisition"])
    |> Search.add_param(params["patient_id_hash"], ["$match", "subject"])
    |> search_by_encounters(encounters)
    |> Search.add_param(params["status"], ["$match", "status"])
    |> Search.add_param(code, ["$match", "code.identifier.value"])
    |> Search.add_param(requester_legal_entity, ["$match", "requester_legal_entity.identifier.value"])
    |> Search.add_param(used_by_legal_entity, ["$match", "used_by_legal_entity.identifier.value"])
    |> List.wrap()
    |> Enum.concat([%{"$sort" => %{"inserted_at" => -1}}])
  end

  defp search_by_encounters(search_pipe, nil), do: search_pipe

  defp search_by_encounters(search_pipe, encounters) do
    put_in(search_pipe, ["$match", "context.identifier.value"], %{"$in" => encounters})
  end

  def get_by_episode_id(%{"service_request_id" => id} = params) do
    with :ok <- check_patient(params),
         :ok <- check_episode(params),
         {:ok, %ServiceRequest{} = service_request} <- get_by_id(id),
         encounter_ids <- get_encounter_ids(params),
         true <-
           Enum.any?(encounter_ids, fn encounter_id ->
             to_string(encounter_id) == to_string(service_request.context.identifier.value)
           end) do
      {:ok, service_request}
    else
      false -> nil
      error -> error
    end
  end

  def get_by_id(id, opts \\ []) do
    @collection
    |> Mongo.find_one(%{"_id" => Mongo.string_to_uuid(id)}, opts)
    |> case do
      %{} = service_request ->
        {:ok, ServiceRequest.create(service_request)}

      _ ->
        nil
    end
  end

  def get_by_id_patient_id(id, patient_id_hash) do
    @collection
    |> Mongo.find_one(%{"_id" => Mongo.string_to_uuid(id), "subject" => patient_id_hash})
    |> case do
      %{} = service_request -> {:ok, ServiceRequest.create(service_request)}
      _ -> nil
    end
  end
end
