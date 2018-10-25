defmodule Core.Expectations.IlExpectations do
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

  def expect_employee_users(tax_id, user_id, n \\ 1) do
    expect(IlMock, :get_employee_users, n, fn employee_id, headers ->
      client_id =
        headers[:"x-consumer-metadata"]
        |> Jason.decode!()
        |> Map.get("client_id")

      {:ok,
       %{
         "data" => %{
           "id" => employee_id,
           "legal_entity_id" => client_id,
           "party" => %{
             "id" => UUID.uuid4(),
             "tax_id" => tax_id,
             "users" => [%{"user_id" => user_id}]
           }
         }
       }}
    end)
  end
end
