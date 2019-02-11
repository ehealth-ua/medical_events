defmodule Core.Validators.ServiceRequestReference do
  @moduledoc false

  use Vex.Validator
  alias Core.ServiceRequest
  alias Core.ServiceRequests
  alias Core.Validators.Employee

  @status_active ServiceRequest.status(:active)

  def validate(value, options) do
    case ServiceRequests.get_by_id(value) do
      nil ->
        error(options, "Referral with such id is not found")

      {:ok, %ServiceRequest{status: @status_active, used_by: nil}} ->
        error(options, "Service request must be used")

      {:ok, %ServiceRequest{status: @status_active, used_by: used_by, expiration_date: expiration_date}} ->
        with :ok <- validate_used_by(used_by.identifier.value, options),
             :ok <- validate_expiration_date(expiration_date, options) do
          :ok
        end

      _ ->
        error(options, "Incoming referral is not active")
    end
  end

  defp validate_used_by(id, options) do
    client_id = Keyword.get(options, :client_id)
    ets_key = Employee.get_key(id)

    case Employee.get_data(ets_key, id) do
      nil ->
        error(options, "Service request must be related to the same legal entity")

      %{} = employee ->
        :ets.insert(:message_cache, {ets_key, employee})

        if employee.legal_entity_id == client_id do
          :ok
        else
          error(options, "Service request must be related to the same legal entity")
        end
    end
  end

  defp validate_expiration_date(nil, _), do: :ok

  defp validate_expiration_date(expiration_date, options) do
    datetime = Keyword.get(options, :datetime)

    case DateTime.compare(expiration_date, datetime) do
      :lt -> error(options, "Service request expiration date must be a datetime greater than or equal")
      _ -> :ok
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
