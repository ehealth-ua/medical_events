defmodule Core.Episode do
  @moduledoc false

  use Core.Schema
  alias Core.Period
  alias Core.Reference

  @status_active "active"
  @status_closed "closed"
  @status_cancelled "entered_in_error"

  def status(:active), do: @status_active
  def status(:closed), do: @status_closed
  def status(:cancelled), do: @status_cancelled

  embedded_schema do
    field(:id, presence: true)
    field(:name)
    field(:status)
    field(:status_history)
    field(:type)
    field(:diagnosis)
    field(:managing_organization, presence: true, reference: [path: "managing_organization"])
    field(:period, presence: true, reference: [path: "period"])
    field(:care_manager, presence: true, reference: [path: "care_manager"])
    field(:encounters)

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"managing_organization", v} -> {:managing_organization, Reference.create(v)}
        {"period", v} -> {:period, Period.create(v)}
        {"care_manager", v} -> {:care_manager, Reference.create(v)}
        {k, v} -> {String.to_atom(k), v}
      end)
    )
  end
end
