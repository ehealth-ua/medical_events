defmodule Core.Validators.CacheTest do
  @moduledoc false

  @behaviour Core.Validators.CacheBehaviour

  def get_json_schema(_key), do: {:ok, nil}

  def set_json_schema(_key, _schema), do: :ok

  def get_dictionaries do
    {:ok,
     [
       %{"name" => "eHealth/resources", "values" => ["condition"]},
       %{"name" => "eHealth/ICD10/conditions", "values" => ["A10"]}
     ]}
  end

  def set_dictionaries(_), do: :ok
end
