defmodule Api.Web.AllergyIntoleranceView do
  @moduledoc false

  use ApiWeb, :view
  alias Core.ReferenceView

  def render("show.json", %{allergy_intolerance: allergy_intolerance}) do
    allergy_intolerance_fields = ~w(
      verification_status
      clinical_status
      id
      type
      category
      criticality
      primary_source
    )a

    allergy_intolerance_data = %{
      context: ReferenceView.render(allergy_intolerance.context),
      code: ReferenceView.render(allergy_intolerance.code),
      onset_date_time: ReferenceView.render_date(allergy_intolerance.onset_date_time),
      asserted_date: ReferenceView.render_date(allergy_intolerance.asserted_date),
      last_occurrence: ReferenceView.render_date(allergy_intolerance.last_occurrence)
    }

    allergy_intolerance
    |> Map.take(allergy_intolerance_fields)
    |> Map.merge(allergy_intolerance_data)
    |> Map.merge(ReferenceView.render_source(allergy_intolerance.source))
  end
end
