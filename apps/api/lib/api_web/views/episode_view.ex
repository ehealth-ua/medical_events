defmodule Api.Web.EpisodeView do
  @moduledoc false

  use ApiWeb, :view
  alias Scrivener.Page

  def render("index.json", %{paging: %Page{entries: episodes}, patient_id: patient_id}) do
    episodes
    |> Enum.map(&Map.get(&1, "episode"))
    |> render_many(__MODULE__, "show.json", as: :episode, patient_id: patient_id)
  end

  def render("show.json", %{episode: episode, patient_id: patient_id}) do
    # TODO add diagnoses_hstr

    episode
    |> Map.take(~w(id type status name period))
    |> Map.put("patient_id", patient_id)
    |> Map.put("managing_organization", episode["managing_organization"]["identifier"])
    |> Map.put("care_manager", episode["care_manager"]["identifier"])
  end
end
