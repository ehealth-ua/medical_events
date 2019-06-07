defmodule Core.Validators.LegalEntity do
  @moduledoc false

  alias Core.CacheHelper
  alias Core.Headers
  import Core.ValidationError

  @rpc_worker Application.get_env(:core, :rpc_worker)

  def validate(legal_entity_id, options) do
    ets_key = "legal_entity_#{legal_entity_id}"

    case get_data(ets_key, legal_entity_id) do
      {:ok, legal_entity} ->
        :ets.insert(CacheHelper.get_cache_key(), {ets_key, legal_entity})

        if Map.get(legal_entity, :status) == Keyword.get(options, :status) do
          :ok
        else
          error(options, Keyword.get(options, :messages)[:status])
        end

      _ ->
        error(options, "LegalEntity with such ID is not found")
    end
  end

  defp get_data(ets_key, legal_entity_id) do
    case :ets.lookup(CacheHelper.get_cache_key(), ets_key) do
      [{^ets_key, legal_entity}] -> {:ok, legal_entity}
      _ -> @rpc_worker.run("ehealth", EHealth.Rpc, :legal_entity_by_id, [legal_entity_id])
    end
  end
end
