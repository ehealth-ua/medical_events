defmodule Core.Validators.DictionaryReference do
  @moduledoc """
  Validate dictionary value based on referenced field value
  """

  alias Core.CodeableConcept
  alias Core.Coding
  alias Core.Dictionaries
  alias Ecto.Changeset
  import Core.ValidationError

  def validate_change(field, value, options \\ [referenced_field: "system", field: "code"]) do
    do_validate_change(field, value, options)
  end

  defp do_validate_change(field, value, options)
       when is_atom(field) and is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce([], fn {v, k}, acc ->
      case validate(Changeset.apply_changes(v), options) do
        :ok ->
          acc

        [{:error, _, _, message}] ->
          Keyword.put(acc, :"#{field}[#{k}]", message)
      end
    end)
  end

  defp do_validate_change(field, value, options) do
    case validate(Changeset.apply_changes(value), options) do
      :ok -> []
      [{:error, _, _, message}] -> Keyword.new([{field, message}])
    end
  end

  def validate(%Coding{} = value, options) do
    field = String.to_atom(Keyword.get(options, :field))
    referenced_field = String.to_atom(Keyword.get(options, :referenced_field))
    field = Map.get(value, field)
    referenced_field = Map.get(value, referenced_field)

    with {:ok, dictionaries} <- Dictionaries.get_dictionaries(),
         %{"values" => values} <- Enum.find(dictionaries, fn %{"name" => name} -> name == referenced_field end),
         true <- Map.has_key?(values, field) do
      :ok
    else
      _ ->
        if Keyword.has_key?(options, :path) do
          {:error, "#{Keyword.get(options, :path)}", :dictionary_reference,
           "Value #{field} not found in the dictionary #{referenced_field}"}
        else
          error(options, "Value #{field} not found in the dictionary #{referenced_field}")
        end
    end
  end

  def validate([], _), do: :ok

  def validate([%CodeableConcept{} | _] = values, options) do
    errors =
      values
      |> Enum.with_index()
      |> Enum.reduce([], fn {value, i}, acc ->
        case validate(value, Keyword.put(options, :path, "#{Keyword.get(options, :path)}.#{i}")) do
          :ok -> acc
          error -> acc ++ [error]
        end
      end)

    case errors do
      [] -> :ok
      _ -> errors
    end
  end

  def validate(%CodeableConcept{} = value, options) do
    errors =
      value.coding
      |> Enum.with_index()
      |> Enum.reduce([], fn {value, i}, acc ->
        case validate(value, Keyword.put(options, :path, "#{Keyword.get(options, :path)}.#{i}")) do
          :ok -> acc
          error -> acc ++ [error]
        end
      end)

    case errors do
      [] -> :ok
      _ -> errors
    end
  end

  def validate(%{__struct__: _}, _), do: :ok

  def validate(nil, _), do: :ok
end
