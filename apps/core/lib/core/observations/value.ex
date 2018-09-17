defmodule Core.Observations.Value do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.Observations.Values.Quantity
  alias Core.Observations.Values.Range
  alias Core.Observations.Values.Ratio
  alias Core.Observations.Values.SampledData
  alias Core.Period

  embedded_schema do
    field(:type, presence: true)
    field(:value, presence: true, reference: [path: nil])
  end

  def create("value_string", value) do
    %__MODULE__{type: "value_string", value: value}
  end

  def create("value_time", value) do
    %__MODULE__{type: "value_time", value: value}
  end

  def create("value_boolean", value) do
    %__MODULE__{type: "value_boolean", value: value}
  end

  def create("value_date_time", value) do
    datetime = create_datetime(value)
    {:value, %__MODULE__{type: "value_date_time", value: datetime}}
  end

  def create("value_quantity", value) do
    %__MODULE__{type: "value_quantity", value: Quantity.create(value)}
  end

  def create("value_codeable_concept", value) do
    %__MODULE__{type: "value_codeable_concept", value: CodeableConcept.create(value)}
  end

  def create("value_sampled_data", value) do
    %__MODULE__{type: "value_sampled_data", value: SampledData.create(value)}
  end

  def create("value_range", value) do
    %__MODULE__{type: "value_range", value: Range.create(value)}
  end

  def create("value_ratio", value) do
    %__MODULE__{type: "value_ratio", value: Ratio.create(value)}
  end

  def create("value_period", value) do
    %__MODULE__{type: "value_period", value: Period.create(value)}
  end
end

defimpl Vex.Blank, for: Core.Observations.Value do
  def blank?(%Core.Observations.Value{}), do: false
  def blank?(_), do: true
end
