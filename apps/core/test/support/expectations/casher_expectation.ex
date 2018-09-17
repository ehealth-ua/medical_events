defmodule Core.Expectations.CasherExpectation do
  @moduledoc false

  import Mox

  def expect_get_person_data(patient_id, times \\ 1) do
    expect(CasherMock, :get_person_data, times, fn _data, _opts ->
      {:ok, %{"data" => %{"person_ids" => [patient_id]}}}
    end)
  end

  def expect_get_person_data_empty() do
    expect(CasherMock, :get_person_data, fn _data, _opts ->
      {:ok, %{"data" => %{"person_ids" => []}}}
    end)
  end
end
