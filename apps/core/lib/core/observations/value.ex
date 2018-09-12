defmodule Core.Observations.Value do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:type, presence: true)
    field(:value, presence: true, reference: [path: nil])
  end
end

defimpl Vex.Blank, for: Core.Observations.Value do
  def blank?(%Core.Observations.Value{}), do: false
  def blank?(_), do: true
end
