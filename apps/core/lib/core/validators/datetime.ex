defmodule Core.Validators.DateTime do
  @moduledoc false

  use Vex.Validator

  def validate(%DateTime{} = datetime, options) do
    with :ok <- validate_greater_than(datetime, options),
         :ok <- validate_greater_than_or_equal(datetime, options),
         :ok <- validate_less_than(datetime, options),
         :ok <- validate_less_than_or_equal(datetime, options) do
      :ok
    end
  end

  def validate(_, _), do: :ok

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end

  defp validate_greater_than(datetime, options) do
    greater_than = Keyword.get(options, :greater_than)

    if is_nil(greater_than) do
      :ok
    else
      case DateTime.compare(datetime, greater_than) do
        :gt -> :ok
        _ -> error(options, "must be a datetime greater than #{to_string(greater_than)}")
      end
    end
  end

  defp validate_greater_than_or_equal(datetime, options) do
    greater_than_or_equal_to = Keyword.get(options, :greater_than_or_equal_to)

    if is_nil(greater_than_or_equal_to) do
      :ok
    else
      case DateTime.compare(datetime, greater_than_or_equal_to) do
        :lt ->
          error(options, "must be a datetime greater than or equal #{to_string(greater_than_or_equal_to)}")

        _ ->
          :ok
      end
    end
  end

  defp validate_less_than(datetime, options) do
    less_than = Keyword.get(options, :less_than)

    if is_nil(less_than) do
      :ok
    else
      case DateTime.compare(datetime, less_than) do
        :lt -> :ok
        _ -> error(options, "must be a datetime less than #{to_string(less_than)}")
      end
    end
  end

  defp validate_less_than_or_equal(datetime, options) do
    less_than_or_equal_to = Keyword.get(options, :less_than_or_equal_to)

    if is_nil(less_than_or_equal_to) do
      :ok
    else
      case DateTime.compare(datetime, less_than_or_equal_to) do
        :gt -> error(options, "must be a datetime less than or equal #{to_string(less_than_or_equal_to)}")
        _ -> :ok
      end
    end
  end
end
