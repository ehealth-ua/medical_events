defmodule Api.Web.AllergyIntoleranceView do
  @moduledoc false

  use ApiWeb, :view

  alias Core.DateView
  alias Core.ReferenceView
  alias Core.UUIDView

  def render("index.json", %{allergy_intolerances: allergy_intolerances}) do
    render_many(allergy_intolerances, __MODULE__, "show.json", as: :allergy_intolerance)
  end

  def render("show.json", %{allergy_intolerance: allergy_intolerance}) do
    allergy_intolerance_fields = ~w(
      verification_status
      clinical_status
      type
      category
      criticality
      primary_source
      inserted_at
      updated_at
    )a

    allergy_intolerance_data = %{
      id: UUIDView.render(allergy_intolerance.id),
      context: ReferenceView.render(allergy_intolerance.context),
      code: ReferenceView.render(allergy_intolerance.code),
      onset_date_time: DateView.render_datetime(allergy_intolerance.onset_date_time),
      asserted_date: DateView.render_datetime(allergy_intolerance.asserted_date),
      last_occurrence: DateView.render_datetime(allergy_intolerance.last_occurrence)
    }

    allergy_intolerance
    |> Map.take(allergy_intolerance_fields)
    |> Map.merge(allergy_intolerance_data)
    |> Map.merge(ReferenceView.render_source(allergy_intolerance.source))
  end
end
