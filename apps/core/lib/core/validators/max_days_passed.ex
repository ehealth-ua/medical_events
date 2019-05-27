defmodule Core.Validators.MaxDaysPassed do
  @moduledoc false

  def validate(date, options) do
    days_from_now = Keyword.get(options, :max_days_passed)
    today = Date.utc_today()
    days_passed = Date.diff(today, get_date(date))

    if days_from_now > days_passed do
      :ok
    else
      greater_date = Date.add(today, -days_from_now)
      {:error, Keyword.get(options, :message, "Date must be greater than #{greater_date}")}
    end
  end

  defp get_date(%DateTime{} = datetime), do: DateTime.to_date(datetime)
  defp get_date(value), do: value
end
