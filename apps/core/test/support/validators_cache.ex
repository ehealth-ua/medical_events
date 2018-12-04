defmodule Core.Validators.CacheTest do
  @moduledoc false

  @behaviour Core.Validators.CacheBehaviour

  def get_json_schema(_key), do: {:ok, nil}

  def set_json_schema(_key, _schema), do: :ok

  def get_dictionaries do
    {:ok,
     [
       %{"name" => "eHealth/reason_explanations", "values" => %{"429060002" => "429060002"}},
       %{"name" => "eHealth/report_origins", "values" => %{"employee" => "employee"}},
       %{"name" => "eHealth/vaccination_target_diseases", "values" => %{"1857005" => "1857005"}},
       %{"name" => "eHealth/vaccination_authorities", "values" => %{"WVO" => "WVO", "1857005" => "1857005"}},
       %{"name" => "eHealth/observation_categories", "values" => %{"1" => "1"}},
       %{"name" => "eHealth/ICPC2/actions", "values" => %{"action" => "action"}},
       %{"name" => "eHealth/ICPC2/reasons", "values" => %{"reason" => "reason", "A02" => "A02"}},
       %{"name" => "eHealth/encounter_classes", "values" => %{"AMB" => "AMB"}},
       %{"name" => "eHealth/allergy_intolerances_codes", "values" => %{"227493005" => "227493005", "1" => "1"}},
       %{"name" => "eHealth/vaccine_codes", "values" => %{"FLUVAX" => "FLUVAX"}},
       %{"name" => "eHealth/vaccination_dose_statuse_reasons", "values" => %{"coldchbrk" => "coldchbrk"}},
       %{"name" => "eHealth/vaccination_dose_statuses", "values" => %{"1" => "1"}},
       %{"name" => "eHealth/vaccination_routes", "values" => %{"IM" => "IM"}},
       %{"name" => "eHealth/observation_methods", "values" => %{"1" => "1"}},
       %{"name" => "eHealth/observation_interpretations", "values" => %{"1" => "1"}},
       %{"name" => "eHealth/body_sites", "values" => %{"1" => "1"}},
       %{"name" => "eHealth/condition_severities", "values" => %{"1" => "1"}},
       %{"name" => "eHealth/condition_stages", "values" => %{"1" => "1"}},
       %{"name" => "eHealth/encounter_types", "values" => %{"inpatient" => "inpatient", "outpatient" => "outpatient"}},
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
