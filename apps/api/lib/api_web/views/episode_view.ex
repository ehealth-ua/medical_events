defmodule Api.Web.EpisodeView do
  @moduledoc false

  use ApiWeb, :view

  alias Api.Web.DiagnosesHistoryView
  alias Api.Web.DiagnosisView
  alias Core.ReferenceView
  alias Core.StatusHistoryView
  alias Core.UUIDView
  alias Scrivener.Page

  def render("index.json", %{paging: %Page{entries: episodes}}) do
    render_many(episodes, __MODULE__, "show.json", as: :episode)
  end

  def render("summary.json", %{paging: %Page{entries: episodes}}) do
    render_many(episodes, __MODULE__, "short.json", as: :episode)
  end

  def render("show.json", %{episode: episode}) do
    episode
    |> Map.take(~w(
      status
      name
      explanatory_letter
      closing_summary
      inserted_at
      updated_at
    )a)
    |> Map.merge(%{
      id: UUIDView.render(episode.id),
      type: ReferenceView.render(episode.type),
      status_reason: ReferenceView.render(episode.status_reason),
      period: ReferenceView.render_date_period(episode.period),
      diagnoses_history:
        DiagnosesHistoryView.render("diagnoses_history.json", diagnoses_history: episode.diagnoses_history),
      managing_organization: ReferenceView.render(episode.managing_organization),
      care_manager: ReferenceView.render(episode.care_manager),
      status_history: StatusHistoryView.render("index.json", %{statuses_history: episode.status_history}),
      current_diagnoses: DiagnosisView.render("diagnoses.json", diagnoses: episode.current_diagnoses || [])
    })
  end

  def render("short.json", %{episode: episode}) do
    episode
    |> Map.take(~w(
      status
      name
      inserted_at
      updated_at
    )a)
    |> Map.merge(%{
      id: UUIDView.render(episode.id),
      period: ReferenceView.render_date_period(episode.period)
    })
  end
end
