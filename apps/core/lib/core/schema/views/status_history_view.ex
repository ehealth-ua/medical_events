defmodule Core.StatusHistoryView do
  @moduledoc false

  alias Core.DateView
  alias Core.ReferenceView
  alias Core.StatusHistory
  alias Core.UUIDView

  def render("index.json", %{statuses_history: statuses_history}) do
    Enum.map(statuses_history, &render("show.json", %{status_history: &1}))
  end

  def render("show.json", %{status_history: %StatusHistory{} = status_history}) do
    %{
      status: status_history.status,
      inserted_at: DateView.render_datetime(status_history.inserted_at),
      inserted_by: UUIDView.render(status_history.inserted_by),
      status_reason: ReferenceView.render(status_history.status_reason)
    }
  end
end
