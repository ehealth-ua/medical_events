defmodule Core.Validators.CacheTest do
  @moduledoc false

  @behaviour Core.Validators.CacheBehaviour

  def get_json_schema(_key), do: {:ok, nil}

  def set_json_schema(_key, _schema), do: :ok

  def get_dictionaries do
    {:ok,
     [
       %{"name" => "eHealth/resources", "values" => %{"condition" => "test"}},
       %{"name" => "eHealth/ICD10/conditions", "values" => %{"A10" => "test", "A11" => "test", "A70" => "test"}},
       %{"name" => "eHealth/ICPC2/conditions", "values" => %{"B10" => "test"}},
       %{"name" => "eHealth/observations_codes", "values" => %{"B70" => "test"}}
     ]}
  end

  def set_dictionaries(_), do: :ok
end
