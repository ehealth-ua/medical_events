defmodule Core.Validators.ServiceGroupReference do
  @moduledoc false

  use Vex.Validator

  @worker Application.get_env(:core, :rpc_worker)

  def validate(service_group_id, options) do
    case @worker.run("ehealth", EHealth.Rpc, :service_group_by_id, [to_string(service_group_id)]) do
      {:ok, _} ->
        :ok

      _ ->
        {:error, message(options, "Service group with such ID is not found")}
    end
  end
end
