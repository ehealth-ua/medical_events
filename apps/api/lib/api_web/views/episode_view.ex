defmodule Api.Web.EpisodeView do
  @moduledoc false

  use ApiWeb, :view
  alias Api.Web.ReferenceView
  alias Api.Web.UUIDView
  alias Scrivener.Page

  def render("index.json", %{paging: %Page{entries: episodes}, patient_id: patient_id}) do
    render_many(episodes, __MODULE__, "show.json", as: :episode, patient_id: patient_id)
  end

  def render("show.json", %{episode: episode, patient_id: patient_id}) do
    # TODO add diagnoses_hstr

    episode
    |> Map.take(~w(type status name)a)
    |> Map.put(:id, UUIDView.render(episode.id))
    |> Map.put(:period, ReferenceView.render(episode.period))
    |> Map.put(:patient_id, patient_id)
    |> Map.put(:managing_organization, ReferenceView.render(episode.managing_organization))
    |> Map.put(:care_manager, ReferenceView.render(episode.care_manager))
  end
end
