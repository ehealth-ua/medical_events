defmodule Core.Patients.RiskAssessments.ExtendedReference do
  @moduledoc false

  use Core.Schema
  alias Core.Reference

  embedded_schema do
    field(:text)
    field(:references, reference: [path: "references"])
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"references", v} ->
          {:references, Enum.map(v, &Reference.create/1)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end

defimpl Vex.Blank, for: Core.Patients.RiskAssessments.ExtendedReference do
  def blank?(%Core.Patients.RiskAssessments.ExtendedReference{}), do: false
  def blank?(_), do: true
end
