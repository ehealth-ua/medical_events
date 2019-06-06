defmodule Core.Validators.Division do
  @moduledoc false

  import Core.ValidationError

  @rpc_worker Application.get_env(:core, :rpc_worker)

  def validate(division_id, options) do
    ets_key = "division_#{division_id}"

    case get_data(ets_key, division_id) do
      {:ok, division} ->
        with :ok <- validate_field({:status, :status}, division, options),
             :ok <- validate_field({:legal_entity_id, :legal_entity_id}, division, options) do
          :ok
        end

      _ ->
        error(options, "Division with such ID is not found")
    end
  end

  def validate_field({field, remote_field}, division, options) do
    if is_nil(Keyword.get(options, field)) or Map.get(division, remote_field) == Keyword.get(options, field) do
      :ok
    else
      error(options, Keyword.get(options, :messages)[field])
    end
  end

  defp get_data(ets_key, division_id) do
    case :ets.lookup(:message_cache, ets_key) do
      [{^ets_key, division}] -> {:ok, division}
      _ -> @rpc_worker.run("ehealth", EHealth.Rpc, :division_by_id, [division_id])
    end
  end
end
