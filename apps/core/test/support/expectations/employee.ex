defmodule Core.Expectations.Employee do
  @moduledoc false

  import Mox

  def expect_doctor(client_id, n \\ 1) do
    expect(IlMock, :get_employee, n, fn id, _ ->
      {:ok,
       %{
         "data" => %{
           "id" => id,
           "status" => "APPROVED",
           "employee_type" => "DOCTOR",
           "legal_entity" => %{"id" => client_id},
           "party" => %{
             "first_name" => "foo",
             "second_name" => "bar",
             "last_name" => "baz"
           }
         }
       }}
    end)
  end
end
