defmodule Core.Validators.Drfo do
  @moduledoc false

  use Vex.Validator
  alias Core.Rpc
  alias Core.Validators.Signature

  @worker Application.get_env(:core, :rpc_worker)

  def validate(employee_id, options) do
    user_id = Keyword.get(options, :user_id)
    client_id = Keyword.get(options, :client_id)
    drfo = Keyword.get(options, :drfo)

    with {:ok, employee_ids} <- @worker.run("ehealth", Rpc, :employees_by_user_id_client_id, [user_id, client_id]),
         {true, _} <- {employee_id in employee_ids, "Employees related to this party_id not in current MSP"},
         tax_id <- @worker.run("ehealth", Rpc, :tax_id_by_employee_id, [employee_id]),
         {:ok, _} <- {Signature.validate_drfo(drfo, tax_id), "Signer DRFO doesn't match with requester tax_id"} do
      :ok
    else
      {_, message} -> error(options, message)
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
