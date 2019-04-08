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

  @collection ServiceRequest.metadata().collection

  def list(%{"patient_id_hash" => patient_id_hash, "episode_id" => episode_id} = params) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         {:ok, %Episode{}} <- Episodes.get_by_id(patient_id_hash, episode_id),
         encounters <- Encounters.get_episode_encounters(patient_id_hash, Mongo.string_to_uuid(episode_id)),
         true <-
           Enum.any?(encounters, fn %{"episode_id" => encounter_episode_id} ->
             to_string(encounter_episode_id) == episode_id
           end) do
      paging_params = Map.take(params, ["page", "page_size"])

      with [_ | _] = pipeline <-
             search_service_requests_pipe(params, Enum.map(encounters, &Map.get(&1, "encounter_id"))),
           %Page{entries: service_requests} = page <-
             Paging.paginate(
               :aggregate,
               @collection,
               pipeline,
               paging_params
             ) do
        {:ok, %Page{page | entries: Enum.map(service_requests, &ServiceRequest.create/1)}}
      else
        _ -> {:ok, Paging.create()}
      end
    else
      false -> nil
      error -> error
    end
  end

  def search(params) do
    search_params = Map.take(params, ~w(requisition status))
    paging_params = Map.take(params, ~w(page page_size))

    with :ok <- JsonSchema.validate(:service_request_search, search_params),
         [_ | _] = pipeline <- search_service_requests_search_pipe(params),
         %Page{entries: service_requests} = page <-
           Paging.paginate(
             :aggregate,
             @collection,
             pipeline,
             paging_params
           ) do
      {:ok, %Page{page | entries: Enum.map(service_requests, &ServiceRequest.create/1)}}
    end
  end

  defp search_service_requests_pipe(%{"patient_id_hash" => patient_id_hash} = params, encounters) do
    %{"$match" => %{"subject" => patient_id_hash, "context.identifier.value" => %{"$in" => encounters}}}
    |> Search.add_param(params["status"], ["$match", "status"])
    |> List.wrap()
    |> Enum.concat([%{"$sort" => %{"inserted_at" => -1}}])
  end

  defp search_service_requests_search_pipe(%{"requisition" => requisition} = params) do
    %{"$match" => %{"requisition" => Encryptor.encrypt(requisition)}}
    |> Search.add_param(params["status"], ["$match", "status"])
    |> List.wrap()
    |> Enum.concat([%{"$sort" => %{"inserted_at" => -1}}])
  end

  def get_by_episode_id(patient_id_hash, episode_id, id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         {:ok, %Episode{}} <- Episodes.get_by_id(patient_id_hash, episode_id),
         {:ok, %ServiceRequest{} = service_request} <- get_by_id(id),
         encounters <- Encounters.get_episode_encounters(patient_id_hash, Mongo.string_to_uuid(episode_id)),
         true <-
           Enum.any?(encounters, fn %{"episode_id" => encounter_episode_id} ->
             to_string(encounter_episode_id) == episode_id
           end),
         true <-
           Enum.any?(encounters, fn %{"encounter_id" => encounter_id} ->
             to_string(encounter_id) == to_string(service_request.context.identifier.value)
           end) do
      {:ok, service_request}
    else
      false -> nil
      error -> error
    end
  end

  def get_by_id(id) do
    @collection
    |> Mongo.find_one(%{"_id" => Mongo.string_to_uuid(id)})
    |> case do
      %{} = service_request -> {:ok, ServiceRequest.create(service_request)}
      _ -> nil
    end
  end
end
