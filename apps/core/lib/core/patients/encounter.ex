defmodule Core.Encounter do
  @moduledoc false

  use Core.Schema

  embedded_schema do
    field(:id, presence: true)
    field(:status)
    field(:status_history)
    field(:period)
    field(:class)
    field(:types)
    field(:incoming_referrals)
    field(:duration)
    field(:reasons)
    field(:diagnoses)
    field(:service_provider)
    field(:division)
    field(:actions)
    field(:signed_content_links)

    timestamps()
    changed_by()
  end

  def create_encounter(data) do
    struct(__MODULE__, Enum.map(data, fn {k, v} -> {String.to_atom(k), v} end))
  end
end
