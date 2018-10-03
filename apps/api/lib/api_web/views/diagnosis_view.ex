defmodule Api.Web.DiagnosisView do
  @moduledoc false

  use ApiWeb, :view
  alias Core.ReferenceView

  def render("diagnoses.json", %{diagnoses: diagnoses}) do
    render_many(diagnoses, __MODULE__, "show.json", as: :diagnosis)
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
