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
        Enum.find(diagnosis.code.coding, fn coding ->
          coding.system == required_system
        end)
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
