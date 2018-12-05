defmodule Core.Validators.ServiceRequestReference do
  @moduledoc false

  use Vex.Validator
  alias Core.ServiceRequest
  alias Core.ServiceRequests

  @status_active ServiceRequest.status(:active)

  def validate(value, options) do
    case ServiceRequests.get_by_id(value) do
      nil ->
        error(options, "Referral with such id is not found")

      {:ok, %ServiceRequest{status: @status_active}} ->
        :ok

      _ ->
        error(options, "Incoming referral is not active")
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
