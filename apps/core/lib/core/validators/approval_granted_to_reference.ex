defmodule Core.Validators.ApprovalGrantedToReference do
  @moduledoc false

  use Vex.Validator
  alias Core.Rpc

  @rpc_worker Application.get_env(:core, :rpc_worker)

  def validate(value, options) do
    user_id = Keyword.get(options, :user_id)
    client_id = Keyword.get(options, :client_id)

    with {:ok, employee_ids} <- @rpc_worker.run("ehealth", Rpc, :employees_by_user_id_client_id, [user_id, client_id]),
         {true, _} <- {value in employee_ids, "Employee does not related to user"} do
      :ok
    else
      {_, message} -> error(options, message)
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end