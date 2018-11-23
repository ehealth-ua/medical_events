defmodule Core.Validators.DictionaryReference do
  @moduledoc """
  Validate dictionary value based on referenced field value
  """

  use Vex.Validator
  alias Core.CodeableConcept

  @validator_cache Application.get_env(:core, :cache)[:validators]

  def validate(%CodeableConcept{} = value, options) do
    field = String.to_atom(Keyword.get(options, :field))
    referenced_field = String.to_atom(Keyword.get(options, :referenced_field))
    coding = hd(value.coding)
    field = Map.get(coding, field)
    referenced_field = Map.get(coding, referenced_field)

    with {:ok, dictionaries} <- @validator_cache.get_dictionaries(),
         %{"values" => values} <- Enum.find(dictionaries, fn %{"name" => name} -> name == referenced_field end),
         true <- Map.has_key?(values, field) do
      :ok
    else
      _ -> error(options, "Value #{field} not found in the dictionary #{referenced_field}")
    end
  end

  def validate(nil, _), do: :ok

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
