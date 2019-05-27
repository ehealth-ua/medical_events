defmodule Core.Validators.DiagnosisCondition do
  @moduledoc false

  alias Core.Conditions

  def validate(value, options) do
    ets_key = "condition_#{value}"
    conditions = Keyword.get(options, :conditions)
    patient_id_hash = Keyword.get(options, :patient_id_hash)
    matched_condition = Enum.find(conditions, &(Map.get(&1, :_id) == value))

    if matched_condition do
      add_to_cache(ets_key, %{"code" => matched_condition.code})
      :ok
    else
      case Conditions.get_by_id(patient_id_hash, value) do
        nil ->
          {:error, Keyword.get(options, :message, "Condition with such id is not found")}

        {:ok, condition} ->
          add_to_cache(ets_key, %{"code" => condition.code})
          :ok
      end
    end
  end

  defp add_to_cache(ets_key, condition) do
    :ets.insert(:message_cache, {ets_key, condition})
  end
end
