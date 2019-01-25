defmodule Core.RiskAssessment do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.Patients.RiskAssessments.ExtendedReference
  alias Core.Patients.RiskAssessments.Prediction
  alias Core.Patients.RiskAssessments.Reason
  alias Core.Reference

  @status_preliminary "preliminary"
  @status_final "final"
  @status_entered_in_error "entered_in_error"

  def status(:preliminary), do: @status_preliminary
  def status(:final), do: @status_final
  def status(:entered_in_error), do: @status_entered_in_error

  embedded_schema do
    field(:id, presence: true, mongo_uuid: true)
    field(:status, presence: true)
    field(:method)

    field(:code,
      presence: true,
      dictionary_reference: [path: "code", referenced_field: "system", field: "code"]
    )

    field(:context, presence: true, reference: [path: "context"])
    field(:asserted_date, presence: true)
    field(:performer, presence: true, reference: [path: "performer"])
    field(:reason, reference: [path: "reason"])
    field(:basis, reference: [path: "basis"])
    field(:predictions, reference: [path: "predictions"])
    field(:mitigation)
    field(:comment)

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"method", v} ->
          {:method, CodeableConcept.create(v)}

        {"code", v} ->
          {:code, CodeableConcept.create(v)}

        {"context", v} ->
          {:context, Reference.create(v)}

        {"asserted_date", v} ->
          {:asserted_date, create_datetime(v)}

        {"performer", v} ->
          {:performer, Reference.create(v)}

        {"reason", %{"type" => type, "value" => value}} ->
          {:reason, Reason.create(type, value)}

        {"reason_codeable_concept", value} ->
          {:reason, Reason.create("reason_codeable_concept", value)}

        {"reason_reference", value} ->
          {:reason, Reason.create("reason_reference", value)}

        {"basis", v} ->
          {:basis, ExtendedReference.create(v)}

        {"predictions", v} ->
          {:predictions, Enum.map(v, &Prediction.create/1)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
