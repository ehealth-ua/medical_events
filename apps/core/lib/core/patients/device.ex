defmodule Core.Device do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.Period
  alias Core.Reference
  alias Core.Source

  @status_active "active"
  @status_inactive "inactive"
  @status_entered_in_error "entered_in_error"
  @status_unknown "unknown"

  def status(:active), do: @status_active
  def status(:inactive), do: @status_inactive
  def status(:entered_in_error), do: @status_entered_in_error
  def status(:unknown), do: @status_unknown

  embedded_schema do
    field(:id, presence: true, mongo_uuid: true)
    field(:status, presence: true)
    field(:asserted_date, presence: true)
    field(:usage_period, presence: true, reference: [path: "usage_period"])
    field(:context, presence: true, reference: [path: "context"])
    field(:primary_source, strict_presence: true)
    field(:source, presence: true, reference: [path: "source"])
    field(:type, presence: true)
    field(:lot_number)
    field(:manufacturer)
    field(:manufacture_date)
    field(:expiration_date)
    field(:model)
    field(:version)
    field(:note)

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"asserted_date", v} ->
          {:asserted_date, create_datetime(v)}

        {"usage_period", v} ->
          {:usage_period, Period.create(v)}

        {"context", v} ->
          {:context, Reference.create(v)}

        {"report_origin", v} ->
          {:source, %Source{type: "report_origin", value: CodeableConcept.create(v)}}

        {"asserter", v} ->
          {:source, %Source{type: "asserter", value: Reference.create(v)}}

        {"source", %{"type" => type, "value" => value}} ->
          {:source, Source.create(type, value)}

        {"type", v} ->
          {:type, CodeableConcept.create(v)}

        {"manufacture_date", v} ->
          {:manufacture_date, create_datetime(v)}

        {"expiration_date", v} ->
          {:expiration_date, create_datetime(v)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
