defmodule Core.Expectations.MPIExpectations do
  @moduledoc false

  import Mox

  def expect_person(id, n \\ 1) do
    expect(WorkerMock, :run, n, fn
      _, _, :get_auth_method, [^id] ->
        {:ok, %{"type" => "OTP", "phone_number" => "+38#{Enum.random(1_000_000_000..9_999_999_999)}"}}
    end)
  end

  def expect_person_offline_auth_method(id, n \\ 1) do
    expect(WorkerMock, :run, n, fn
      _, _, :get_auth_method, [^id] ->
        {:ok, %{"type" => "OFFLINE"}}
    end)
  end
end
