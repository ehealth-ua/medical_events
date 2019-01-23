defmodule Core.Expectations.OTPVerificationExpectations do
  @moduledoc false

  import Mox

  def expect_otp_verification_initialize(n \\ 1) do
    expect(OTPVerificationMock, :initialize, n, fn _phone_number, _headers ->
      {:ok, %{"data" => []}}
    end)
  end

  def expect_otp_verification_complete(status, n \\ 1) do
    expect(OTPVerificationMock, :complete, n, fn _number, _params, _headers ->
      case status do
        :not_found ->
          {:error, %{"meta" => %{"code" => 404}, "error" => %{"type" => "not_found"}}}

        :error ->
          {:error,
           %{"meta" => %{"code" => 422}, "error" => %{"type" => "forbidden", "message" => "invalid verification code"}}}

        _ ->
          {:ok, %{"meta" => %{"code" => 200}, "data" => %{"status" => "verified"}}}
      end
    end)
  end
end
