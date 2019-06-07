defmodule Core.Services do
  @moduledoc false

  alias Core.CacheHelper

  @worker Application.get_env(:core, :rpc_worker)

  def get_service(service_id) do
    ets_key = "service_#{service_id}"

    case :ets.lookup(CacheHelper.get_cache_key(), ets_key) do
      [{^ets_key, service}] ->
        {:ok, service}

      _ ->
        with {:ok, service} <- @worker.run("ehealth", EHealth.Rpc, :service_by_id, [to_string(service_id)]) do
          :ets.insert(CacheHelper.get_cache_key(), {ets_key, service})
          {:ok, service}
        end
    end
  end
end
