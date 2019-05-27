defmodule Core.Validators.DiagnosesRole do
  @moduledoc false

  import Core.ValidationError

  def validate(diagnoses, options) when is_list(diagnoses) do
    type = Keyword.get(options, :type)

    results =
      Enum.any?(diagnoses, fn diagnosis ->
        Enum.find(diagnosis.role.coding, fn coding ->
          coding.code == type
        end)
      end)

    if results, do: :ok, else: error(options, "Required #{type} value is missing")
  end

  def validate(_, _), do: :ok
end
