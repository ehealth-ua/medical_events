defmodule Core.Validators.Drfo do
  @moduledoc false

  alias Core.DigitalSignature
  alias Core.Validators.Signature

  @worker Application.get_env(:core, :rpc_worker)

  def validate(employee_id, options) do
    if DigitalSignature.config()[:enabled] do
      user_id = Keyword.get(options, :user_id)
      client_id = Keyword.get(options, :client_id)
      drfo = Keyword.get(options, :drfo)

      with {:ok, employee_ids} <-
             @worker.run("ehealth", EHealth.Rpc, :employees_by_user_id_client_id, [user_id, client_id]),
           {true, _} <-
             {to_string(employee_id) in employee_ids, "Employees related to this party_id not in current MSP"},
           tax_id <- @worker.run("ehealth", EHealth.Rpc, :tax_id_by_employee_id, [employee_id]),
           {:ok, _} <- {Signature.validate_drfo(drfo, tax_id), "Signer DRFO doesn't match with requester tax_id"} do
        :ok
      else
        {_, message} ->
          {:error, Keyword.get(options, :message, message)}
      end
    else
      :ok
    end
  end
end
