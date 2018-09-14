defmodule Core.Observations.Values.SampledData do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:origin)
    field(:period)
    field(:factor)
    field(:lower_limit)
    field(:upper_limit)
    field(:dimensions)
    field(:data, presence: true)
  end

  def create(data) do
    struct(__MODULE__, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end

defimpl Vex.Blank, for: Core.Observations.Values.SampledData do
  def blank?(%Core.Observations.Values.SampledData{}), do: false
  def blank?(_), do: true
end
