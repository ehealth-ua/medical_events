defmodule Api.Web.EncounterView do
  @moduledoc false

  use ApiWeb, :view

  alias Core.ReferenceView
  alias Core.UUIDView


  def render("index.json", %{encounters: encounters}) do
    render_many(encounters, __MODULE__, "show.json", as: :encounter)
  end

  def render("show.json", %{encounter: encounter}) do
    encounter_fields = ~w(
      status
    )a

    encounter_data = %{
      id: UUIDView.render(encounter.id),
      date: Date.to_string(encounter.date),
      visit: ReferenceView.render(encounter.visit),
      episode: ReferenceView.render(encounter.episode),
      class: ReferenceView.render(encounter.class),
      type: ReferenceView.render(encounter.type),
      incoming_referrals: ReferenceView.render(encounter.incoming_referrals),
      performer: ReferenceView.render(encounter.performer),
      reasons: ReferenceView.render(encounter.reasons),
      diagnoses: ReferenceView.render(encounter.diagnoses),
      actions: ReferenceView.render(encounter.actions),
      division: ReferenceView.render(encounter.division)
    }

    encounter
    |> Map.take(encounter_fields)
    |> Map.merge(encounter_data)
  end
end
