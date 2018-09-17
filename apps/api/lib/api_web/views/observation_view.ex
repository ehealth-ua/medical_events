defmodule Api.Web.ObservationView do
  @moduledoc false

  use ApiWeb, :view
  alias Api.Web.ReferenceView

  def render("index.json", %{observations: observations}) do
    render_many(observations, __MODULE__, "show.json", as: :observation)
  end

  def render("show.json", %{observation: observation}) do
    observation_fields = ~w(
      status
      based_on
      issued
      primary_source
      comment
      method
    )a

    observation_data = %{
      id: observation._id,
      categories: ReferenceView.render(observation.categories),
      context: ReferenceView.render(observation.context),
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
