defmodule Core.Expectations.IlExpectations do
  @moduledoc false

  import Mox

  def expect_legal_entity(response, n \\ 1) do
    expect(WorkerMock, :run, n, fn _, _, :legal_entity_by_id, _ ->
      {:ok, response}
    end)
  end

  def expect_division(response, n \\ 1) do
    expect(WorkerMock, :run, n, fn _, _, :division_by_id, _ ->
      {:ok, response}
    end)
  end

  def expect_doctor(client_id, n \\ 1) do
    expect(WorkerMock, :run, n, fn
      _, _, :employee_by_id, [id] ->
        {:ok,
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
         }}
    end)
  end

  def expect_employees_by_user_id_client_id(employee_ids, n \\ 1) when is_list(employee_ids) do
    expect(WorkerMock, :run, n, fn _, _, :employees_by_user_id_client_id, _ ->
      {:ok, employee_ids}
    end)
  end

  def expect_employee_users(tax_id, client_id, user_id, n \\ 1) do
    expect(WorkerMock, :run, n, fn _, _, :employee_by_id_users_short, [employee_id] ->
      {:ok,
       %{
         id: employee_id,
         legal_entity_id: client_id,
         party: %{
           id: UUID.uuid4(),
           tax_id: tax_id,
           users: [%{user_id: user_id}]
         }
       }}
    end)
  end
end
