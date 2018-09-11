defmodule Core.Patients.Immunizations.VaccinationProtocol do
  @moduledoc false

  use Core.Schema
  alias Core.CodeableConcept

  embedded_schema do
    field(:dose_sequence, number: [greater_than: 0])
    field(:description)
    field(:authority, reference: [path: "authority"])
    field(:series)
    field(:series_doses, number: [greater_than: 0])
    field(:target_diseases, presence: true, reference: [path: "target_diseases"])
    field(:dose_status, presence: true)
    field(:dose_status_reason)
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"target_diseases", v} ->
          {:target_diseases, Enum.map(v, &CodeableConcept.create/1)}

        {"dose_status", v} ->
          {:dose_status, CodeableConcept.create(v)}

        {"dose_status_reason", v} ->
          {:dose_status_reason, CodeableConcept.create(v)}

        {"codeable_concept", v} ->
          {:codeable_concept, CodeableConcept.create(v)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end

defimpl Vex.Blank, for: Core.Patients.Immunizations.VaccinationProtocol do
  def blank?(%Core.Patients.Immunizations.VaccinationProtocol{}), do: false
  def blank?(_), do: true
end
