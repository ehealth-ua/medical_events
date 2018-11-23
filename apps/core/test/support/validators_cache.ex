defmodule Core.Validators.CacheTest do
  @moduledoc false

  @behaviour Core.Validators.CacheBehaviour

  def get_json_schema(_key), do: {:ok, nil}

  def set_json_schema(_key, _schema), do: :ok

  def get_dictionaries do
    {:ok,
     [
       %{"name" => "eHealth/encounter_types", "values" => %{"AMB" => "AMB"}},
       %{
         "name" => "eHealth/episode_closing_reasons",
         "values" => %{
           "legal_entity" => "legal_entity"
         }
       },
       %{
         "name" => "eHealth/cancellation_reasons",
         "values" => %{
           "misspelling" => "misspelling"
         }
       },
       %{
         "name" => "eHealth/resources",
         "values" => %{
           "1" => "1",
           "employee" => "test",
           "condition" => "test",
           "referral" => "test",
           "encounter" => "test",
           "legal_entity" => "test"
         }
       },
       %{
         "name" => "eHealth/ICD10/condition_codes",
         "values" => %{
           "A10" => "test",
           "A11" => "test",
           "A70" => "test",
           "J11" => "J11",
           "R80" => "R80",
           "code" => "code"
         }
       },
       %{
         "name" => "eHealth/ICPC2/condition_codes",
         "values" => %{"A10" => "test", "B10" => "test", "R80" => "R80", "T90" => "T90", "code" => "code"}
       },
       %{
         "name" => "eHealth/LOINC/observation_codes",
         "values" => %{
           "1" => "1",
           "condition" => "condition",
           "B70" => "test",
           "8310-5" => "8310-5",
           "8462-4" => "8462-4",
           "8480-6" => "8480-6",
           "code" => "code"
         }
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
