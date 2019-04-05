defmodule Api.Web.ObservationView do
  @moduledoc false

  use ApiWeb, :view

  alias Core.ReferenceView
  alias Core.UUIDView

  def render("index.json", %{observations: observations}) do
    render_many(observations, __MODULE__, "show.json", as: :observation)
  end

  def render("show.json", %{observation: observation}) do
    observation_fields = ~w(
      status
      primary_source
      comment
      issued
      inserted_at
      updated_at
    )a

    observation_data = %{
      id: UUIDView.render(observation._id),
      based_on: ReferenceView.render(observation.based_on),
      method: ReferenceView.render(observation.method),
      categories: ReferenceView.render(observation.categories),
      context: ReferenceView.render(observation.context),
      diagnostic_report: ReferenceView.render(observation.diagnostic_report),
      interpretation: ReferenceView.render(observation.interpretation),
      code: ReferenceView.render(observation.code),
      body_site: ReferenceView.render(observation.body_site),
      reference_ranges: ReferenceView.render(observation.reference_ranges),
      components: ReferenceView.render(observation.components)
    }

    observation
    |> Map.take(observation_fields)
    |> Map.merge(observation_data)
    |> Map.merge(ReferenceView.render_effective_at(observation.effective_at))
    |> Map.merge(ReferenceView.render_source(observation.source))
    |> Map.merge(ReferenceView.render_value(observation.value))
  end
end
