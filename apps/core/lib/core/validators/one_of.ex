defmodule Core.Validators.OneOf do
  @moduledoc false

  alias Core.ValidationError
  alias Core.Validators.Error

  def validate(data, one_of_params) when is_map(one_of_params) do
    errors =
      Enum.reduce_while(one_of_params, [], fn {k, v}, acc ->
        with true <- Regex.match?(~r/^(\$|\$\.[\w.]+)$/, k),
             path <- String.split(k, "."),
             one_of_fields <- v["params"],
             :ok <- validate_params(one_of_fields),
             :ok <-
               do_validate(%{
                 data: data,
                 path: path,
                 one_of_fields: one_of_fields,
                 required: Map.get(v, "required", false),
                 indexes: [],
                 error_path: []
               }) do
          {:cont, acc}
        else
          {:validation_error, error} -> {:cont, acc ++ [error]}
          _ -> {:halt, :argument_error}
        end
      end)

    case errors do
      :argument_error -> raise(ArgumentError, message: "Inavalid parameters for oneOf validation function")
      [] -> :ok
      errors -> Error.dump(errors)
    end
  end

  def validate(_, _), do: raise(ArgumentError, message: "Inavalid parameters for oneOf validation function")

  defp validate_params(validation_params) when is_list(validation_params) and length(validation_params) > 1, do: :ok
  defp validate_params(_), do: :argument_error

  defp do_validate(%{data: data, indexes: indexes} = state) when is_list(data) do
    errors =
      data
      |> Enum.with_index()
      |> Enum.reduce_while([], fn {value, i}, acc ->
        case do_validate(%{state | data: value, indexes: indexes ++ [i]}) do
          :ok -> {:cont, acc}
          {:validation_error, error} -> {:cont, acc ++ [error]}
          _ -> {:halt, :argument_error}
        end
      end)

    case errors do
      :argument_error -> :argument_error
      [] -> :ok
      errors -> {:validation_error, errors}
    end
  end

  defp do_validate(%{path: ["$" | []], indexes: indexes, error_path: error_path} = state) do
    check_one_of_fields(%{state | indexes: [], error_path: add_path(error_path, "$", indexes)})
  end

  defp do_validate(%{path: ["$" | path_keys], indexes: indexes, error_path: error_path} = state) do
    do_validate(%{state | path: path_keys, indexes: [], error_path: add_path(error_path, "$", indexes)})
  end

  defp do_validate(%{data: data, path: [path_key | []], indexes: indexes, error_path: error_path} = state) do
    if Map.has_key?(data, path_key) do
      check_one_of_fields(%{
        state
        | data: Map.get(data, path_key),
          indexes: [],
          error_path: add_path(error_path, path_key, indexes)
      })
    else
      :argument_error
    end
  end

  defp do_validate(%{data: data, path: [path_key | path_keys], indexes: indexes, error_path: error_path} = state) do
    if Map.has_key?(data, path_key) do
      do_validate(%{
        state
        | data: Map.get(data, path_key),
          path: path_keys,
          indexes: [],
          error_path: add_path(error_path, path_key, indexes)
      })
    else
      :argument_error
    end
  end

  defp add_path(error_path, nil, []), do: error_path

  defp add_path(error_path, nil, indexes) do
    indexes =
      indexes
      |> Enum.map(&"[#{&1}]")
      |> Enum.join()

    List.update_at(error_path, Enum.count(error_path) - 1, fn last -> "#{last}#{indexes}" end)
  end

  defp add_path(error_path, key, []), do: error_path ++ ["#{key}"]

  defp add_path(error_path, key, indexes) do
    indexes =
      indexes
      |> Enum.map(&"[#{&1}]")
      |> Enum.join()

    error_path ++ ["#{key}#{indexes}"]
  end

  defp check_one_of_fields(%{data: data, indexes: indexes} = state) when is_list(data) do
    errors =
      data
      |> Enum.with_index()
      |> Enum.reduce([], fn {value, i}, acc ->
        case check_one_of_fields(%{state | data: value, indexes: indexes ++ [i]}) do
          :ok -> acc
          {:validation_error, error} -> acc ++ [error]
        end
      end)

    case errors do
      [] -> :ok
      errors -> {:validation_error, errors}
    end
  end

  defp check_one_of_fields(%{data: data, indexes: indexes, error_path: error_path, required: required} = state) do
    data
    |> prepare_validation_result(%{state | indexes: [], error_path: add_path(error_path, nil, indexes)})
    |> check_result(required)
  end

  defp prepare_validation_result(data, %{one_of_fields: one_of_fields, indexes: indexes, error_path: error_path}) do
    Enum.into(one_of_fields, %{}, fn one_of_field ->
      {error_path |> add_path(one_of_field, indexes) |> Enum.join("."), Map.has_key?(data, one_of_field)}
    end)
  end

  defp check_result(result, true) do
    case result |> Map.values() |> Enum.filter(&Kernel.==(&1, true)) |> length() do
      0 -> build_error(Map.keys(result), "At least one of the parameters must be present")
      1 -> :ok
      _ -> build_error(Map.keys(result), "Only one of the parameters must be present")
    end
  end

  defp check_result(result, _) do
    if result |> Map.values() |> Enum.filter(&Kernel.==(&1, true)) |> length() <= 1 do
      :ok
    else
      build_error(Map.keys(result), "Only one of the parameters must be present")
    end
  end

  defp build_error(paths, error_message) do
    {:validation_error,
     Enum.map(paths, fn path ->
       %ValidationError{
         description: error_message,
         path: path,
         params: paths,
         rule: "oneOf"
       }
     end)}
  end
end
