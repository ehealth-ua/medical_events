defmodule Core.Validators.MedicationRequestReference do
  @moduledoc false

  use Vex.Validator

  @worker Application.get_env(:core, :rpc_worker)

  def validate(medication_request_id, options) do
    case @worker.run("ops", OPS.Rpc, :medication_request_by_id, [to_string(medication_request_id)]) do
      nil ->
        {:error, message(options, "Medication request with such ID is not found")}

      %{} ->
        :ok
    end
  end
end
