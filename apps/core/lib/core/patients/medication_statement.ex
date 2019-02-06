defmodule Core.MedicationStatement do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.Reference
  alias Core.Source

  @status_active "active"
  @status_stopped "stopped"
  @status_entered_in_error "entered_in_error"

  def status(:active), do: @status_active
  def status(:stopped), do: @status_stopped
  def status(:entered_in_error), do: @status_entered_in_error

  embedded_schema do
    field(:id, presence: true, mongo_uuid: true)
    field(:based_on, reference: [path: "based_on"])
    field(:status, presence: true)
    field(:medication_code, presence: true)
    field(:context, presence: true, reference: [path: "context"])
    field(:effective_period)
    field(:asserted_date, presence: true)
    field(:primary_source, strict_presence: true)
    field(:source, presence: true, reference: [path: "source"])
    field(:note)
    field(:dosage)

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"based_on", v} ->
          {:based_on, Reference.create(v)}

        {"medication_code", v} ->
          {:medication_code, CodeableConcept.create(v)}

        {"context", v} ->
          {:context, Reference.create(v)}

        {"asserted_date", v} ->
          {:asserted_date, create_datetime(v)}

        {"asserter", v} ->
          {:source, %Source{type: "asserter", value: Reference.create(v)}}

        {"report_origin", v} ->
          {:source, %Source{type: "report_origin", value: CodeableConcept.create(v)}}

        {"source", %{"type" => type, "value" => value}} ->
          {:source, Source.create(type, value)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
