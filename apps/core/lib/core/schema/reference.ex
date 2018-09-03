defmodule Core.Reference do
  @moduledoc false

  use Core.Schema
  alias Core.Identifier

  embedded_schema do
    field(:identifier, presence: true, reference: [path: "identifier"])
    field(:display_value)
  end

  def create(data) do
    %__MODULE__{
      identifier: Identifier.create(Map.get(data, "identifier")),
      display_value: Map.get(data, "display_value")
    }
  end
end

defimpl Vex.Blank, for: Core.Reference do
  def blank?(%Core.Reference{}), do: false
  def blank?(_), do: true
end
