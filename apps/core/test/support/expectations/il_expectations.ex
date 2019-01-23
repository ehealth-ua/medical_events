defmodule Core.Expectations.IlExpectations do
  @moduledoc false

  import Mox

  def expect_doctor(client_id, n \\ 1) do
    expect(WorkerMock, :run, n, fn
      _, _, :employee_by_id, [id] ->
        %{
          id: id,
          status: "APPROVED",
          employee_type: "DOCTOR",
          legal_entity_id: client_id,
          party: %{
            first_name: "foo",
            second_name: "bar",
            last_name: "baz"
          }
        }
    end)
  end

  def expect_employees_by_user_id_client_id(employee_ids, n \\ 1) when is_list(employee_ids) do
    expect(WorkerMock, :run, n, fn _, _, :employees_by_user_id_client_id, _ ->
      {:ok, employee_ids}
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
