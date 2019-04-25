defmodule Core.Services do
  @moduledoc false

  @worker Application.get_env(:core, :rpc_worker)

  def get_service(service_id) do
    ets_key = "service_#{service_id}"

    case :ets.lookup(:message_cache, ets_key) do
      [{^ets_key, service}] ->
        {:ok, service}

      _ ->
        with {:ok, service} <- @worker.run("ehealth", EHealth.Rpc, :service_by_id, [to_string(service_id)]) do
          :ets.insert(:message_cache, {ets_key, service})
          {:ok, service}
        end
    end
  end
end
