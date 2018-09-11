defmodule Core.Immunization do
  @moduledoc false

  use Core.Schema
  alias Core.CodeableConcept
  alias Core.Observations.Values.Quantity
  alias Core.Patients.Immunizations.Explanation
  alias Core.Patients.Immunizations.Reaction
  alias Core.Patients.Immunizations.VaccinationProtocol
  alias Core.Reference
  alias Core.Source

  @status_completed "completed"
  @status_entered_in_error "entered_in_error"

  def status(:completed), do: @status_completed
  def status(:entered_in_error), do: @status_entered_in_error

  embedded_schema do
    field(:id, presence: true)
    field(:status, presence: true)
    field(:not_given, strict_presence: true)
    field(:vaccine_code, presence: true)
    field(:context, presence: true, reference: [path: "context"])
    field(:date, presence: true, reference: [path: "date"])
    field(:primary_source, strict_presence: true)
    field(:source, presence: true, reference: [path: "source"])
    field(:legal_entity, reference: [path: "legal_entity"])
    field(:manufacturer, reference: [path: "manufacturer"])
    field(:lot_number)
    field(:expiration_date, reference: [path: "expiration_date"])
    field(:site, reference: [path: "site"])
    field(:route, reference: [path: "route"])
    field(:dose_quantity, reference: [path: "dose_quantity"])
    field(:explanation)
    field(:reactions, reference: [path: "reactions"])
    field(:vaccination_protocols, reference: [path: "vaccination_protocols"])

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"context", v} ->
          {:context, Reference.create(v)}

        {"date", v} ->
          date = v |> Date.from_iso8601!() |> Date.to_erl()
          {:date, {date, {0, 0, 0}} |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")}

        {"issued", v} ->
          {:ok, datetime, _} = DateTime.from_iso8601(v)
          {:issued, datetime}

        {"report_origin", v} ->
          {:source, %Source{type: "report_origin", value: CodeableConcept.create(v)}}

        {"performer", v} ->
          {:source, %Source{type: "performer", value: Reference.create(v)}}

        {"legal_entity", v} ->
          {:legal_entity, Reference.create(v)}

        {"manufacturer", v} ->
          {:manufacturer, CodeableConcept.create(v)}

        {"expiration_date", v} ->
          date = v |> Date.from_iso8601!() |> Date.to_erl()
          {:expiration_date, {date, {0, 0, 0}} |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")}

        {"site", v} ->
          {:site, CodeableConcept.create(v)}

        {"route", v} ->
          {:route, CodeableConcept.create(v)}

        {"explanation", v} ->
          {:explanation, Explanation.create(v)}

        {"dose_quantity", v} ->
          {:dose_quantity, Quantity.create(v)}

        {"reactions", v} ->
          {:reactions, Enum.map(v, &Reaction.create/1)}

        {"vaccination_protocols", v} ->
          {:vaccination_protocols, Enum.map(v, &VaccinationProtocol.create/1)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
