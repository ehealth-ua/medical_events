defmodule Api.Web.DiagnosesHistoryView do
  @moduledoc false

  use ApiWeb, :view

  alias Api.Web.DiagnosisView
  alias Core.DiagnosesHistory
  alias Core.ReferenceView

  def render("diagnoses_history.json", %{diagnoses_history: diagnoses_history}) do
    render_many(diagnoses_history, __MODULE__, "show.json", as: :diagnos_history)
  end

  def render("show.json", %{diagnos_history: %DiagnosesHistory{} = diagnos_history}) do
    %{
      date: DateTime.to_date(diagnos_history.date),
      is_active: diagnos_history.is_active,
      evidence: ReferenceView.render(diagnos_history.evidence),
      diagnoses: DiagnosisView.render("diagnoses.json", diagnoses: diagnos_history.diagnoses)
    }
  end
end
