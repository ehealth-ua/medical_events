defmodule Core.AllertyIntolerance do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:id, presence: true)
    field(:clinical_status)
    field(:verification_status)
    field(:type)
    field(:category)
    field(:criticality)
    field(:code)
    field(:onset_date_time)
    field(:asserted_date)
    field(:recorder)
    field(:asser)
    field(:last_occurance)
    field(:context)

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(__MODULE__, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end
