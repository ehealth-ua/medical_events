defmodule Core.Observation do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:id, presence: true)
    field(:based_on)
    field(:status)
    field(:categories)
    field(:code)
    field(:patient_id, presence: true)
    field(:encounter)
    field(:effective_date_time)
    field(:effective_period)
    field(:issued)
    field(:performers)
    field(:value)
    field(:interpretation)
    field(:comment)
    field(:body_side)
    field(:method)
    field(:reference_rage)
    field(:component)

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(__MODULE__, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end
