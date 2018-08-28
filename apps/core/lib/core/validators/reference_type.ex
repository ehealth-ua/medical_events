defmodule Core.Validators.ReferenceType do
  @moduledoc false

  use Vex.Validator

  def validate(references, options) when is_list(references) do
    type = Keyword.get(options, :type)

    results =
      Enum.any?(references, fn reference ->
        Enum.find(reference.identifier.type.coding, fn coding ->
          coding.code == type
        end)
      end)

    if results, do: :ok, else: {:error, message(options, "Required reference to #{type} is missing")}
  end

  def validate(_, _), do: :ok
end
