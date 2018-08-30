defmodule Core.Period do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:start, presence: true)
    field(:end)
  end

  def create(data) do
    %__MODULE__{
      start: create_date(Map.get(data, "start")),
      end: create_date(Map.get(data, "end"))
    }
  end

  defp create_date(nil), do: nil

  defp create_date(value) when is_binary(value) do
    {:ok, datetime, _} = DateTime.from_iso8601(value)
    datetime
  end
end

defimpl Vex.Blank, for: Core.Period do
  def blank?(%Core.Period{}), do: false
  def blank?(_), do: true
end
