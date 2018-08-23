defmodule Core.Validators.ReferenceType do
  @moduledoc false

  use Vex.Validator
  alias Core.Validators.Vex

  def validate([] = references, [type: type] = options) do
    results =
      Enum.any?(references, fn reference ->
        Enum.find(reference.identifier.type.coding, fn coding ->
          coding == type
        end)
      end)

    if results, do: :ok, else: message(options, "Required reference to #{type} is missing")
  end

  def validate(_, _), do: :ok
end
