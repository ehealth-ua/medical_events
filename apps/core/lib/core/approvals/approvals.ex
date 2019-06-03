defmodule Core.Approvals do
  @moduledoc false

  alias Core.Approval
  alias Core.Mongo
  alias Core.Patients
  alias Core.Patients.Validators
  alias Core.ValidationError
  alias Core.Validators.Error
  require Logger

  @collection Approval.collection()

  @worker Application.get_env(:core, :rpc_worker)
  @status_new Approval.status(:new)
  @status_active Approval.status(:active)
  @otp_verification_api Application.get_env(:core, :microservices)[:otp_verification]

  def verify(
        %{"patient_id_hash" => patient_id_hash, "patient_id" => patient_id, "id" => id} = params,
        user_id
      ) do
    code = Map.get(params, "code")

    with %{} = patient <- Patients.get_by_id(patient_id_hash, projection: [status: true]),
         :ok <- Validators.is_active(patient),
         {:ok, %Approval{status: @status_new} = approval} <-
           get_by_id(id, projection: [status: true, patient_id: true]),
         :ok <- validate_patient(approval, patient_id_hash),
         {:ok, auth_method} <- get_person_auth_method(patient_id),
         :ok <- verify_auth(auth_method, code) do
      set = %{"status" => @status_active, "updated_by" => user_id, "updated_at" => DateTime.utc_now()}

      {:ok, %{matched_count: 1, modified_count: 1}} =
        Mongo.update_one(@collection, %{"_id" => approval._id}, %{"$set" => set})

      get_by_id(UUID.binary_to_string!(approval._id.binary))
    else
      {:ok, %Approval{status: status}} ->
        {:error, {:conflict, "Approval in status #{status} can not be verified"}}

      err ->
        err
    end
  end

  def get_by_id(id, opts \\ []) do
    @collection
    |> Mongo.find_one(%{"_id" => Mongo.string_to_uuid(id)}, opts)
    |> case do
      %{} = approval -> {:ok, Approval.create(approval)}
      _ -> nil
    end
  end

  def get_by_patient_id_granted_to_episode_id_status(patient_id, employee_ids, episode_id, status) do
    @collection
    |> Mongo.find(%{
      "patient_id" => Patients.get_pk_hash(patient_id),
      "status" => status,
      "granted_to.identifier.value" => %{"$in" => Enum.map(employee_ids, &Mongo.string_to_uuid/1)},
      "granted_resources" => %{
        "$elemMatch" => %{
          "identifier.type.coding.code" => "episode_of_care",
          "identifier.value" => Mongo.string_to_uuid(episode_id)
        }
      }
    })
    |> Enum.map(&Approval.create/1)
  end

  def get_person_auth_method(person_id) do
    case @worker.run("mpi", MPI.Rpc, :get_auth_method, [person_id]) do
      nil ->
        {:error, "Person is not found", 404}

      {:ok, %{} = auth_method} ->
        {:ok, auth_method}

      _ ->
        {:error, "Failed to get person data", 500}
    end
  end

  defp verify_auth(%{"type" => "OTP", "phone_number" => phone_number}, code) do
    case @otp_verification_api.complete(phone_number, %{code: code}, []) do
      {:ok, _} ->
        :ok

      _error ->
        Error.dump(%ValidationError{description: "Invalid verification code", path: "$.otp"})
    end
  end

  defp verify_auth(_, _), do: :ok

  defp validate_patient(%Approval{patient_id: patient_id_hash}, patient_id_hash), do: :ok

  defp validate_patient(_, _) do
    {:error, {:access_denied, "Access denied - request to other patient's approval"}}
  end
end
