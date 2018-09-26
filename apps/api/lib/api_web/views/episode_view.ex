defmodule Api.Web.EpisodeView do
  @moduledoc false

  use ApiWeb, :view


  alias Api.Web.DiagnosesHistoryView
  alias Core.ReferenceView
  alias Core.UUIDView
  alias Scrivener.Page

  def render("index.json", %{paging: %Page{entries: episodes}, patient_id: patient_id}) do
    render_many(episodes, __MODULE__, "show.json", as: :episode, patient_id: patient_id)
  end

  def render("show.json", %{episode: episode, patient_id: patient_id}) do
    episode
    |> Map.take(~w(type status name explanatory_letter closing_summary inserted_at)a)
    |> Map.put(:cancellation_reason, ReferenceView.render(episode.cancellation_reason))
    |> Map.put(:closing_reason, ReferenceView.render(episode.closing_reason))
    |> Map.put(:id, UUIDView.render(episode.id))
    |> Map.put(:period, ReferenceView.render(episode.period))
    |> Map.put(:patient_id, patient_id)
    |> Map.put(
      :diagnoses_history,
      DiagnosesHistoryView.render("diagnoses_history.json", diagnoses_history: episode.diagnoses_history)
    )
    |> Map.put(:managing_organization, ReferenceView.render(episode.managing_organization))
    |> Map.put(:care_manager, ReferenceView.render(episode.care_manager))
  end
end
