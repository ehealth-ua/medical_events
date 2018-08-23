defmodule Core.Immunization do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:id, presence: true)
    field(:status)
    field(:not_given)
    field(:vaccine_code)
    field(:context)
    field(:date)
    field(:primary_source)
    field(:report_origin)
    field(:legal_entity)
    field(:manufacturer)
    field(:lot_number)
    field(:expiration_date)
    field(:site)
    field(:route)
    field(:dose_quantity)
    field(:practitioner)
    field(:explanation)
    field(:reactions)
    field(:vaccination_protocol)

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(__MODULE__, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end
