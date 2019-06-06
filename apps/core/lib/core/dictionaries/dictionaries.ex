defmodule Core.Dictionaries do
  @moduledoc false

  @validator_cache Application.get_env(:core, :cache)[:validators]
  @rpc_worker Application.get_env(:core, :rpc_worker)

  def get_dictionaries do
    case @validator_cache.get_dictionaries() do
      {:ok, nil} ->
        params = [%{"is_active" => true}]

        with {:ok, dictionaries} <- @rpc_worker.run("ehealth", EHealth.Rpc, :get_dictionaries, [params]) do
          @validator_cache.set_dictionaries(dictionaries)
          {:ok, dictionaries}
        end

      {:ok, dictionaries} ->
        {:ok, dictionaries}
    end
  end
end
