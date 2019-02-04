defmodule Core.Microservices.OTPVerification do
  @moduledoc false

  use Core.Microservices

  @behaviour Core.Behaviours.OTPVerificationBehaviour

  def initialize(number, headers \\ []) do
    post("/verifications", Jason.encode!(%{phone_number: number}), headers)
  end

  def search(number, headers \\ []) do
    get("/verifications/#{number}", headers)
  end

  def complete(number, params, headers \\ []) do
    patch("/verifications/#{number}/actions/complete", Jason.encode!(params), headers)
  end

  def send_sms(phone_number, body, type, headers \\ []) do
    post("/sms/send", Jason.encode!(%{phone_number: phone_number, body: body, type: type}), headers)
  end
end
