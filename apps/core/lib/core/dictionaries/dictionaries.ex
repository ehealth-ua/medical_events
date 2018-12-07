defmodule Core.Dictionaries do
  @moduledoc false

  @validator_cache Application.get_env(:core, :cache)[:validators]
  @il_microservice Application.get_env(:core, :microservices)[:il]

  def get_dictionaries do
    case @validator_cache.get_dictionaries() do
      {:ok, nil} ->
        with {:ok, %{"data" => dictionaries}} <- @il_microservice.get_dictionaries(%{"is_active" => true}, []) do
          @validator_cache.set_dictionaries(dictionaries)
          {:ok, dictionaries}
        end

      {:ok, dictionaries} ->
        {:ok, dictionaries}
    end
  end
end
