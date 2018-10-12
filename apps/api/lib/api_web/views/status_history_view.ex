defmodule Api.Web.StatusHistoryView do
  @moduledoc false

  use ApiWeb, :view

  alias Core.DateView
  alias Core.ReferenceView
  alias Core.StatusHistory
  alias Core.UUIDView

  def render("statuses_history.json", %{statuses_history: statuses_history}) do
    render_many(statuses_history, __MODULE__, "show.json", as: :status_history)
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
