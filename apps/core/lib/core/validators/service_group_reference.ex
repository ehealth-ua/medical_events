defmodule Core.Validators.ServiceGroupReference do
  @moduledoc false

  import Core.ValidationError

  @worker Application.get_env(:core, :rpc_worker)

  def validate(service_group_id, options) do
    case @worker.run("ehealth", EHealth.Rpc, :service_group_by_id, [to_string(service_group_id)]) do
      {:ok, %{is_active: false}} ->
        error(options, "Service group should be active")

      {:ok, %{request_allowed: false}} ->
        error(options, "Request is not allowed for the service group")

      {:ok, _} ->
        :ok

      _ ->
        error(options, "Service group with such ID is not found")
    end
  end
end
