defmodule Core.Period do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:start, presence: true)
    field(:end)
  end

  def create(data) do
    %__MODULE__{
      start: create_datetime(Map.get(data, "start")),
      end: create_datetime(Map.get(data, "end"))
    }
  end
end

defimpl Vex.Blank, for: Core.Period do
  def blank?(%Core.Period{}), do: false
  def blank?(_), do: true
end
