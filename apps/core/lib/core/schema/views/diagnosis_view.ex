defmodule Core.DiagnosisView do
  @moduledoc false

  alias Core.Diagnosis
  alias Core.ReferenceView

  def render(%Diagnosis{} = diagnosis) do
    %{
      rank: diagnosis.rank,
      condition: ReferenceView.render(diagnosis.condition),
      role: ReferenceView.render(diagnosis.role)
    }
  end
end
