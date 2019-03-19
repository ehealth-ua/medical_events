defmodule Core.Executor do
  @moduledoc false

  use Core.Schema
  alias Core.Reference

  embedded_schema do
    field(:type, presence: true)
    field(:value, presence: true, reference: [path: "value"])
  end

  def create(%{"reference" => value}) do
    %__MODULE__{type: "reference", value: Reference.create(value)}
  end

  def create(%{"text" => value}) do
    %__MODULE__{type: "string", value: value}
  end
end

defimpl Vex.Blank, for: Core.Executor do
  def blank?(%Core.Executor{}), do: false
  def blank?(_), do: true
end
