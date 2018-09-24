defmodule Api.Web.ImmunizationView do
  @moduledoc false

  use ApiWeb, :view
  alias Core.ReferenceView

  def render("index.json", %{immunizations: immunizations}) do
    render_many(immunizations, __MODULE__, "show.json", as: :immunization)
  end

  def render("show.json", %{immunization: immunization}) do
    immunization_fields = ~w(
      id
      status
      not_given
      primary_source
      manufacturer
      lot_number
    )a

    immunization_data = %{
      vaccine_code: ReferenceView.render(immunization.vaccine_code),
      context: ReferenceView.render(immunization.context),
      date: ReferenceView.render_date(immunization.date),
      legal_entity: ReferenceView.render(immunization.legal_entity),
      expiration_date: ReferenceView.render_date(immunization.expiration_date),
      site: ReferenceView.render(immunization.site),
      route: ReferenceView.render(immunization.route),
      dose_quantity: ReferenceView.render(immunization.dose_quantity),
      reactions: ReferenceView.render(immunization.reactions),
      vaccination_protocols: ReferenceView.render(immunization.vaccination_protocols),
      explanation: ReferenceView.render(immunization.explanation)
    }

    immunization
    |> Map.take(immunization_fields)
    |> Map.merge(immunization_data)
    |> Map.merge(ReferenceView.render_source(immunization.source))
  end
end
