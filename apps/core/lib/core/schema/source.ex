defmodule Core.Source do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.Reference

  embedded_schema do
    field(:type, presence: true)
    field(:value, presence: true, reference: [path: "value"])
  end

  def create("report_origin" = type, value) do
    %__MODULE__{type: type, value: CodeableConcept.create(value)}
  end

  def create("asserter" = type, value) do
    %__MODULE__{type: type, value: Reference.create(value)}
  end

  def create("performer" = type, value) do
    %__MODULE__{type: type, value: Reference.create(value)}
  end
end

defimpl Vex.Blank, for: Core.Source do
  def blank?(%Core.Source{}), do: false
  def blank?(_), do: true
end
