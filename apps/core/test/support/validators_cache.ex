defmodule Core.Validators.CacheTest do
  @moduledoc false

  @behaviour Core.Validators.CacheBehaviour

  def get_json_schema(_key), do: {:ok, nil}

  def set_json_schema(_key, _schema), do: :ok

  def get_dictionaries do
    {:ok,
     [
       %{"name" => "eHealth/resources", "values" => %{"condition" => "test"}},
       %{
         "name" => "eHealth/ICD10/conditions",
         "values" => %{"A10" => "test", "A11" => "test", "A70" => "test", "J11" => "J11", "R80" => "R80"}
       },
       %{
         "name" => "eHealth/ICPC2/conditions",
         "values" => %{"A10" => "test", "B10" => "test", "R80" => "R80", "T90" => "T90"}
       },
       %{
         "name" => "eHealth/observations_codes",
         "values" => %{"B70" => "test", "8310-5" => "8310-5", "8462-4" => "8462-4", "8480-6" => "8480-6"}
       },
       %{
         "name" => "eHealth/SNOMED/service_request_categories",
         "values" => %{"409063005" => "test"}
       },
       %{
         "name" => "eHealth/SNOMED/procedure_codes",
         "values" => %{"128004" => "test"}
       },
       %{
         "name" => "eHealth/SNOMED/service_request_performer_roles",
         "values" => %{"psychiatrist" => "psychiatrist"}
       }
     ]}
  end

  def set_dictionaries(_), do: :ok
end
