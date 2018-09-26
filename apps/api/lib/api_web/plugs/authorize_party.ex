defmodule Api.Web.Plugs.AuthorizeParty do
  @moduledoc """
  Authorizes party, requires `patient_id` request param
  """

  import Plug.Conn

  alias Api.Web.FallbackController
  alias Core.Patients
  alias Core.Redis
  alias Core.Redis.StorageKeys
  alias Plug.Conn

  @casher_api Application.get_env(:core, :microservices)[:casher]

  def init(opts), do: opts

  def call(%Conn{private: conn_data, path_params: params} = conn, _opts) do
    user_id = conn_data[:user_id]
    client_id = conn_data[:client_id]
    patient_id = Map.fetch!(params, "patient_id")

    with {:ok, patient_ids} <- get_patient_ids(user_id, client_id),
         true <- passes_auth?(patient_id, patient_ids),
         {_, %{}} <- {:patient_exists, Patients.get_by_id(patient_id)} do
      conn
    else
      {:patient_exists, _} ->
        conn
        |> FallbackController.call(nil)
        |> halt()

      _ ->
        conn
        |> FallbackController.call(
          {:error, {:access_denied, "Access denied - you have no active declaration with the patient"}}
        )
        |> halt()
    end
  end

  defp get_patient_ids(user_id, client_id) do
    case Redis.get(StorageKeys.person_data(user_id, client_id)) do
      {:ok, patient_ids} ->
        {:ok, patient_ids}

      _ ->
        case @casher_api.get_person_data(%{user_id: user_id, client_id: client_id}, []) do
          {:ok, %{"data" => %{"person_ids" => patient_ids}}} -> {:ok, patient_ids}
          err -> err
        end
    end
  end

  defp passes_auth?(patient_id, patient_ids), do: patient_id in patient_ids
end
