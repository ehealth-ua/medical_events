defmodule Core.ServiceRequests.Occurrence do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:type, presence: true)
    field(:value, presence: true, reference: [path: nil])
  end

  def create("date_time", value) do
    %__MODULE__{type: "date_time", value: value}
  end

  def create("period", value) do
    %__MODULE__{type: "period", value: value}
  end
end

defimpl Vex.Blank, for: Core.ServiceRequests.Occurrence do
  def blank?(%Core.ServiceRequests.Occurrence{}), do: false
  def blank?(_), do: true
end
