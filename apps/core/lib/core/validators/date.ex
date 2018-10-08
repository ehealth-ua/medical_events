defmodule Core.Validators.Date do
  @moduledoc false

  use Vex.Validator

  def validate(%DateTime{} = datetime, options) do
    validate(get_date(datetime), options)
  end

  def validate(%Date{} = date, options) do
    with :ok <- validate_greater_than(date, options),
         :ok <- validate_greater_than_or_equal(date, options),
         :ok <- validate_less_than(date, options),
         :ok <- validate_less_than_or_equal(date, options) do
      :ok
    end
  end

  def validate(_, _), do: :ok

  def validate_expiration(date, days_from_now) do
    today = Date.utc_today()
    days_passed = Date.diff(today, get_date(date))

    if days_from_now > days_passed do
      :ok
    else
      greater_date = Date.add(today, -days_from_now)

      {:error, "Date must be greater than #{greater_date}"}
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end

  defp validate_greater_than(date, options) do
    greater_than = options |> Keyword.get(:greater_than) |> get_date()

    if is_nil(greater_than) do
      :ok
    else
      case Date.compare(date, greater_than) do
        :gt -> :ok
        _ -> error(options, "must be a date greater than #{to_string(greater_than)}")
      end
    end
  end

  defp validate_greater_than_or_equal(date, options) do
    greater_than_or_equal_to = options |> Keyword.get(:greater_than_or_equal_to) |> get_date

    if is_nil(greater_than_or_equal_to) do
      :ok
    else
      case Date.compare(date, greater_than_or_equal_to) do
        :lt ->
          error(options, "must be a date greater than or equal #{to_string(greater_than_or_equal_to)}")

        _ ->
          :ok
      end
    end
  end

  defp validate_less_than(date, options) do
    less_than = options |> Keyword.get(:less_than) |> get_date

    if is_nil(less_than) do
      :ok
    else
      case Date.compare(date, less_than) do
        :lt -> :ok
        _ -> error(options, "must be a date less than #{to_string(less_than)}")
      end
    end
  end

  defp validate_less_than_or_equal(date, options) do
    less_than_or_equal_to = options |> Keyword.get(:less_than_or_equal_to) |> get_date

    if is_nil(less_than_or_equal_to) do
      :ok
    else
      case Date.compare(date, less_than_or_equal_to) do
        :gt -> error(options, "must be a date less than or equal #{to_string(less_than_or_equal_to)}")
        _ -> :ok
      end
    end
  end

  defp get_date(%DateTime{} = datetime), do: DateTime.to_date(datetime)
  defp get_date(value), do: value
end
