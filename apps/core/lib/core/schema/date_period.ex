defmodule Core.DatePeriod do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:start, presence: true)
    field(:end)
  end

  def create(data) do
    %__MODULE__{
      start: Map.get(data, "start"),
      end: create_date(Map.get(data, "end"))
    }
  end

  defp create_date(nil), do: nil

  defp create_date(value) when is_binary(value) do
    {:ok, datetime} = Date.from_iso8601(value)
    datetime
  end

  defp create_date(%DateTime{} = value), do: value
end

defimpl Vex.Blank, for: Core.DatePeriod do
  def blank?(%Core.DatePeriod{}), do: false
  def blank?(_), do: true
end
