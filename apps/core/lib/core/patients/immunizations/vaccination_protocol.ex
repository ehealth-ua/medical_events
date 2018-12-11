defmodule Core.Patients.Immunizations.VaccinationProtocol do
  @moduledoc false

  use Core.Schema
  alias Core.CodeableConcept

  embedded_schema do
    field(:dose_sequence, number: [greater_than: 0])
    field(:description)
    field(:authority, dictionary_reference: [path: "authority", referenced_field: "system", field: "code"])
    field(:series)
    field(:series_doses, number: [greater_than: 0])

    field(:target_diseases,
      presence: true,
      dictionary_reference: [path: "target_diseases", referenced_field: "system", field: "code"]
    )

    field(:dose_status,
      presence: true,
      dictionary_reference: [path: "dose_status", referenced_field: "system", field: "code"]
    )

    field(:dose_status_reason,
      dictionary_reference: [path: "dose_status_reason", referenced_field: "system", field: "code"]
    )
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

        {"authority", v} ->
          {:authority, CodeableConcept.create(v)}

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
