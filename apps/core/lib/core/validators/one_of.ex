defmodule Core.Validators.OneOf do
  @moduledoc false

  alias Core.ValidationError, as: CoreValidationError
  alias Core.Validators.Error
  alias EView.Views.ValidationError

  def validate(data, one_of_params, opts \\ [])

  def validate(data, one_of_params, opts) when is_map(one_of_params) do
    errors =
      Enum.reduce_while(one_of_params, [], fn {k, v}, acc ->
        with true <- Regex.match?(~r/^(\$|\$\.[\w.]+)$/, k),
             :ok <-
               do_validate(%{
                 data: data,
                 path: String.split(k, "."),
                 one_of_fields: v,
                 error_path: [],
                 required: false,
                 strict_path_validation: Keyword.get(opts, :strict_path_validation, false)
               }) do
          {:cont, acc}
        else
          {:validation_error, error} -> {:cont, acc ++ error}
          _ -> {:halt, :argument_error}
        end
      end)

    case errors do
      :argument_error ->
        raise(ArgumentError, message: "Inavalid parameters for oneOf validation function")

      [] ->
        :ok

      errors ->
        if Keyword.get(opts, :render_error, true) do
          {:error, errors} = Error.dump(errors)
          {:error, ValidationError.render("422.json", %{schema: errors}), 422}
        else
          Error.dump(errors)
        end
    end
  end

  def validate(_, _, _), do: raise(ArgumentError, message: "Inavalid parameters for oneOf validation function")

  defp do_validate(%{path: ["$" | []], error_path: error_path} = state) do
    check_one_of_fields(%{state | error_path: add_path(error_path, "$", nil)})
  end

  defp do_validate(%{path: ["$" | path_keys], error_path: error_path} = state) do
    do_validate(%{state | path: path_keys, error_path: add_path(error_path, "$", nil)})
  end

  defp do_validate(%{data: data, error_path: error_path} = state) when is_list(data) do
    errors =
      data
      |> Enum.with_index()
      |> Enum.reduce_while([], fn {value, i}, acc ->
        case do_validate(%{state | data: value, error_path: add_path(error_path, nil, i)}) do
          :ok -> {:cont, acc}
          {:validation_error, error} -> {:cont, acc ++ error}
          _ -> {:halt, :argument_error}
        end
      end)

    case errors do
      :argument_error -> :argument_error
      [] -> :ok
      errors -> {:validation_error, errors}
    end
  end

  defp do_validate(
         %{
           data: data,
           path: [path_key | []],
           error_path: error_path,
           strict_path_validation: strict_path_validation
         } = state
       ) do
    cond do
      Map.has_key?(data, path_key) ->
        check_one_of_fields(%{
          state
          | data: Map.get(data, path_key),
            error_path: add_path(error_path, path_key, nil)
        })

      strict_path_validation ->
        :argument_error

      true ->
        :ok
    end
  end

  defp do_validate(
         %{
           data: data,
           path: [path_key | path_keys],
           error_path: error_path,
           strict_path_validation: strict_path_validation
         } = state
       ) do
    cond do
      Map.has_key?(data, path_key) ->
        do_validate(%{
          state
          | data: Map.get(data, path_key),
            path: path_keys,
            error_path: add_path(error_path, path_key, nil)
        })

      strict_path_validation ->
        :argument_error

      true ->
        :ok
    end
  end

  defp add_path([], nil, _), do: []

  defp add_path(error_path, nil, index) do
    List.update_at(error_path, Enum.count(error_path) - 1, fn last -> "#{last}[#{index}]" end)
  end

  defp add_path(error_path, key, nil), do: error_path ++ ["#{key}"]

  defp add_path(error_path, key, index) do
    error_path ++ ["#{key}[#{index}]"]
  end

  defp check_one_of_fields(%{data: data, error_path: error_path} = state) when is_list(data) do
    errors =
      data
      |> Enum.with_index()
      |> Enum.reduce_while([], fn {value, i}, acc ->
        case check_one_of_fields(%{state | data: value, error_path: add_path(error_path, nil, i)}) do
          :ok -> {:cont, acc}
          {:validation_error, error} -> {:cont, acc ++ error}
          _ -> {:halt, :argument_error}
        end
      end)

    case errors do
      :argument_error -> :argument_error
      [] -> :ok
      errors -> {:validation_error, errors}
    end
  end

  defp check_one_of_fields(%{one_of_fields: one_of_fields} = state) when is_list(one_of_fields) do
    errors =
      one_of_fields
      |> Enum.reduce_while([], fn value, acc ->
        case check_one_of_fields(%{state | one_of_fields: value}) do
          :ok -> {:cont, acc}
          {:validation_error, error} -> {:cont, acc ++ error}
          _ -> {:halt, :argument_error}
        end
      end)

    case errors do
      :argument_error -> :argument_error
      [] -> :ok
      errors -> {:validation_error, errors}
    end
  end

  defp check_one_of_fields(%{one_of_fields: one_of_fields} = state) do
    one_of_fields_params = one_of_fields["params"]

    case validate_params(one_of_fields_params) do
      :ok ->
        prepare_validation_result(%{
          state
          | one_of_fields: one_of_fields_params,
            required: Map.get(one_of_fields, "required", false)
        })

      _ ->
        :argument_error
    end
  end

  defp validate_params(validation_params) when is_list(validation_params) and length(validation_params) > 1, do: :ok
  defp validate_params(_), do: :argument_error

  defp prepare_validation_result(%{data: data, one_of_fields: one_of_fields} = state) do
    one_of_fields
    |> Enum.into(%{}, fn one_of_field -> {one_of_field, Map.has_key?(data, one_of_field)} end)
    |> check_result(state)
  end

  defp check_result(result, %{required: true} = state) do
    keys = result |> Enum.filter(fn {_, v} -> v == true end) |> Enum.map(fn {k, _} -> k end)

    case length(keys) do
      0 -> build_error(state)
      1 -> :ok
      _ -> build_error(keys, state)
    end
  end

  defp check_result(result, state) do
    keys = result |> Enum.filter(fn {_, v} -> v == true end) |> Enum.map(fn {k, _} -> k end)
    if length(keys) <= 1, do: :ok, else: build_error(keys, state)
  end

  defp build_error(%{error_path: error_path} = state) do
    {:validation_error,
     [
       %CoreValidationError{
         description: "At least one of the parameters must be present",
         path: Enum.join(error_path, "."),
         params: paths(state),
         rule: "oneOf"
       }
     ]}
  end

  defp build_error(keys, %{error_path: error_path} = state) do
    {:validation_error,
     Enum.map(keys, fn key ->
       %CoreValidationError{
         description: "Only one of the parameters must be present",
         path: error_path |> add_path(key, nil) |> Enum.join("."),
         params: paths(state),
         rule: "oneOf"
       }
     end)}
  end

  defp paths(%{one_of_fields: one_of_fields, error_path: error_path}) do
    Enum.map(one_of_fields, fn one_of_field ->
      error_path |> add_path(one_of_field, nil) |> Enum.join(".")
    end)
  end
end
