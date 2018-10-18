defmodule Api.Web.EpisodeView do
  @moduledoc false

  use ApiWeb, :view

  alias Api.Web.DiagnosesHistoryView
  alias Api.Web.DiagnosisView
  alias Api.Web.StatusHistoryView
  alias Core.ReferenceView
  alias Core.UUIDView
  alias Scrivener.Page

  def render("index.json", %{paging: %Page{entries: episodes}}) do
    render_many(episodes, __MODULE__, "show.json", as: :episode)
  end

  def render("show.json", %{episode: episode}) do
    episode
    |> Map.take(~w(type status name explanatory_letter closing_summary inserted_at)a)
    |> Map.put(:status_reason, ReferenceView.render(episode.status_reason))
    |> Map.put(:id, UUIDView.render(episode.id))
    |> Map.put(:period, ReferenceView.render(episode.period))
    |> Map.put(
      :diagnoses_history,
      DiagnosesHistoryView.render("diagnoses_history.json", diagnoses_history: episode.diagnoses_history)
    )
    |> Map.put(:managing_organization, ReferenceView.render(episode.managing_organization))
    |> Map.put(:care_manager, ReferenceView.render(episode.care_manager))
    |> Map.put(
      :status_history,
      StatusHistoryView.render("statuses_history.json", statuses_history: episode.status_history)
    )
    |> Map.put(:current_diagnoses, DiagnosisView.render("diagnoses.json", diagnoses: episode.current_diagnoses || []))
  end
end
