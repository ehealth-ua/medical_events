defmodule Core.Expectations.OTPVerificationExpectations do
  @moduledoc false

  import Mox

  def expect_otp_verification_initialize(n \\ 1) do
    expect(WorkerMock, :run, n, fn "otp_verification_api", OtpVerification.Rpc, :initialize, [_] ->
      {:ok, %{status: "NEW"}}
    end)
  end

  def expect_otp_verification_complete(status, n \\ 1) do
    expect(WorkerMock, :run, n, fn "otp_verification_api", OtpVerification.Rpc, :complete, [_, _] ->
      case status do
        :ok -> {:ok, %{status: "verified"}}
        :not_found -> nil
        _ -> {:error, {:forbidden, "Invalid verification code"}}
      end
    end)
  end

  def expect_otp_verification_send_sms(n \\ 1) do
    expect(WorkerMock, :run, n, fn "otp_verification_api", OtpVerification.Rpc, :send_sms, [phone_number, body, type] ->
      {:ok,
       %{
         id: UUID.uuid4(),
         phone_number: phone_number,
         body: body,
         type: type
       }}
    end)
  end
end
