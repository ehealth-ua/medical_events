defmodule Api.Web.DiagnosisView do
  @moduledoc false

  use ApiWeb, :view
  alias Api.Web.ReferenceView
  alias Core.Diagnosis

  def render("diagnoses.json", %{diagnoses: diagnosises}) do
    render_many(diagnosises, __MODULE__, "show.json", as: :diagnosis)
  end

  def render("show.json", %{diagnosis: diagnosis}) do
    %{
      rank: diagnosis.rank,
      condition: ReferenceView.render(diagnosis.condition),
      role: ReferenceView.render(diagnosis.role),
      code: ReferenceView.render(diagnosis.code)
    }
  end
end
