defmodule Core.Patients.Encounters.Validations do
  @moduledoc false

  alias Core.Headers
  alias Core.Microservices.DigitalSignature
  alias Core.Validators.Signature

  @il_microservice Application.get_env(:core, :microservices)[:il]

  @spec validate_signatures(map, binary, binary, binary) :: :ok | {:error, term}
  def validate_signatures(signer, employee_id, user_id, client_id) do
    if Confex.fetch_env!(:core, DigitalSignature)[:enabled] do
      do_validate_signatures(signer, employee_id, user_id, client_id)
    else
      :ok
    end
  end

  defp do_validate_signatures(%{"drfo" => drfo}, employee_id, user_id, client_id)
       when drfo != nil do
    headers = [Headers.create(:user_id, user_id), Headers.create(:client_id, client_id)]
    employee_users_data = @il_microservice.get_employee_users(employee_id, headers)

    with {:ok, %{"data" => %{"party" => party, "legal_entity_id" => legal_entity_id}}} <-
           employee_users_data,
         :ok <- Signature.validate_drfo(drfo, party["tax_id"]),
         :ok <- validate_performer_client(legal_entity_id, client_id),
         :ok <- validate_performer_is_current_user(party["users"], user_id) do
      :ok
    else
      {:ok, response} -> {:error, response}
      err -> err
    end
  end

  defp do_validate_signatures(_, _, _, _), do: {:error, "Invalid drfo"}

  defp validate_performer_is_current_user(users, user_id) do
    users
    |> Enum.any?(&(&1["user_id"] == user_id))
    |> case do
      true -> :ok
      _ -> {:error, "Employee is not performer of encounter"}
    end
  end

  defp validate_performer_client(client_id, client_id), do: :ok

  defp validate_performer_client(_, _),
    do: {:error, "Performer does not belong to current legal entity"}
end
