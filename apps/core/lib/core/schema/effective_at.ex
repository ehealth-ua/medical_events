defmodule Core.EffectiveAt do
  @moduledoc false

  use Core.Schema
  alias Core.Period

  embedded_schema do
    field(:type, presence: true)
    field(:value, presence: true, reference: [path: "value"])
  end

  def create("effective_period" = type, value) do
    %__MODULE__{type: type, value: Period.create(value)}
  end

  def create("effective_date_time" = type, value) do
    %__MODULE__{type: type, value: create_datetime(value)}
  end
end

defimpl Vex.Blank, for: Core.EffectiveAt do
  def blank?(%Core.EffectiveAt{}), do: false
  def blank?(_), do: true
end
