defmodule Core.Reference do
  @moduledoc false

  use Core.Schema
  alias Core.Identifier

  embedded_schema do
    field(:identifier, presence: true)
  end

  def create(data) do
    %__MODULE__{identifier: Identifier.create(Map.get(data, "identifier"))}
  end
end

defimpl Vex.Blank, for: Core.Reference do
  def blank?(%Core.Reference{}), do: false
  def blank?(_), do: true
end
