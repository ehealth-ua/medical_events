defmodule Core.Validators.DiagnosesCode do
  @moduledoc false

  use Vex.Validator

  def validate(diagnoses, options) when is_list(diagnoses) do
    code = Keyword.get(options, :code)

    required_system =
      case code do
        "inpatient" -> "eHealth/ICD10/condition_codes"
        "outpatient" -> "eHealth/ICPC2/condition_codes"
      end

    results =
      Enum.any?(diagnoses, fn diagnosis ->
        ets_key = "condition_#{diagnosis.condition.identifier.value}"

        with [{_, condition}] <- :ets.lookup(:message_cache, ets_key) do
          condition["code"].coding |> hd |> Map.get(:system) == required_system
        end
      end)

    if results do
      :ok
    else
      {:error,
       message(options, "At least one of the diagnosis codes should be defined in the #{required_system} system")}
    end
  end

  def validate(_, _), do: :ok
end
