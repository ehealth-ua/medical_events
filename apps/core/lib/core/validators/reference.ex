defmodule Core.Validators.Reference do
  @moduledoc false

  use Vex.Validator
  alias Core.Validators.Vex

  def validate(%{__meta__: _} = reference, path: path) do
    case Vex.errors(reference) do
      [] ->
        :ok

      errors ->
        Enum.map(errors, fn {:error, field, validator, error_message} ->
          {:error, "#{get_subpath(path)}#{field}", validator, error_message}
        end)
    end
  end

  def validate(references, path: path) when is_list(references) do
    errors =
      references
      |> Enum.with_index()
      |> Enum.reduce([], fn {reference, i}, acc ->
        case validate(reference, path: "#{get_subpath(path)}[#{i}]") do
          :ok -> acc
          errors -> acc ++ errors
        end
      end)

    case errors do
      [] -> :ok
      _ -> errors
    end
  end

  def validate(_, _), do: :ok

  defp get_subpath(nil), do: ""
  defp get_subpath(path), do: path <> "."
end
