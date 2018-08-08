defmodule Core.Condition do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:id, presence: true)
    field(:clinical_status)
    field(:verification_status)
    field(:severity)
    field(:code)
    field(:body_sites)
    field(:patient_id, presence: true)
    field(:context)
    field(:onset_date)
    field(:asserted_date)
    field(:asserter)
    field(:stage)
    field(:evidences)

    timestamps()
    changed_by()
  end

  def create_condition(data) do
    struct(__MODULE__, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end
