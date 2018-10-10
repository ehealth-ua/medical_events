defmodule Core.DatePeriod do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:start, presence: true)
    field(:end)
  end

  def create(data) do
    %__MODULE__{
      start: create_date(data["start"]),
      end: create_date(data["end"])
    }
  end

  defp create_date(nil), do: nil
  defp create_date(%DateTime{} = value), do: DateTime.to_date(value)

  defp create_date(value) when is_binary(value) do
    {:ok, date} = Date.from_iso8601(value)
    date
  end
end

defimpl Vex.Blank, for: Core.DatePeriod do
  def blank?(%Core.DatePeriod{}), do: false
  def blank?(_), do: true
end
