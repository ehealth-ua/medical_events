defmodule Api.Web.ImmunizationView do
  @moduledoc false

  use ApiWeb, :view
  alias Core.ReferenceView

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
      date: render_date(immunization.date),
      legal_entity: ReferenceView.render(immunization.legal_entity),
      expiration_date: render_date(immunization.expiration_date),
      site: ReferenceView.render(immunization.site),
      route: ReferenceView.render(immunization.route),
      dose_quantity: ReferenceView.render(immunization.dose_quantity),
      reactions: ReferenceView.render(immunization.reactions),
      vaccination_protocols: ReferenceView.render(immunization.vaccination_protocols)
    }

    immunization
    |> Map.take(immunization_fields)
    |> Map.merge(immunization_data)
    |> Map.merge(ReferenceView.render_source(immunization.source))
    |> Map.merge(ReferenceView.render_explanation(immunization.explanation))
  end

  defp render_date(nil), do: nil
  defp render_date(%DateTime{} = date_time), do: date_time |> DateTime.to_date() |> to_string()
end
