defmodule Core.Validators.SchemaMapper do
  @moduledoc """
  Load dictionaries from Il and put enum rules into json schema
  """

  alias NExJsonSchema.Schema.Root
  require Logger

  @validator_cache Application.get_env(:core, :cache)[:validators]
  @il_microservice Application.get_env(:core, :microservices)[:il]

  def prepare_schema(%Root{schema: schema} = nex_schema, schema_name) do
    case @validator_cache.get_json_schema(schema_name) do
      {:ok, nil} ->
        with {:ok, dictionaries} <- get_dictionaries() do
          new_schema = map_schema(dictionaries, schema)

          prepared_schema = %{nex_schema | schema: new_schema}
          @validator_cache.set_json_schema(schema_name, prepared_schema)
          prepared_schema
        end

      {:ok, cached_schema} ->
        cached_schema

      _ ->
        {:error, {:internal_error, "can't validate json schema"}}
    end
  end

  def map_schema(dictionaries, schema) when length(dictionaries) > 0 do
    Enum.reduce(schema, %{}, &process_schema_value(&1, &2, dictionaries))
  end

  def map_schema(_, schema) do
    Logger.warn(fn -> "Empty dictionaries db" end)
    schema
  end

  defp process_schema_value({k, v}, acc, dictionaries) when is_map(v) do
    Map.put(acc, k, Enum.reduce(v, %{}, &process_schema_value(&1, &2, dictionaries)))
  end

  defp process_schema_value({k = "description", v}, acc, dictionaries) do
    acc = Map.put(acc, k, v)

    with %{"type" => type} <- Regex.named_captures(~r/Dictionary: (?<type>\w+)$/, v),
         %{"values" => values} <- Enum.find(dictionaries, fn %{"name" => name} -> name == type end) do
      Map.put(acc, "enum", Map.keys(values))
    else
      _ -> acc
    end
  end

  defp process_schema_value({k, v}, acc, _) do
    Map.put(acc, k, v)
  end

  defp get_dictionaries do
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
