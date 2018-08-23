defmodule Core.Episode do
  @moduledoc false

  use Core.Schema

  @status_active "active"
  @status_closed "closed"
  @status_cancelled "cancelled"

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
end
