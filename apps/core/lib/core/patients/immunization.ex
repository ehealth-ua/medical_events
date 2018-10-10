defmodule Core.Immunization do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.Maybe
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
    field(:id, presence: true, mongo_uuid: true)
    field(:status, presence: true)
    field(:not_given, strict_presence: true)
    field(:vaccine_code, presence: true)
    field(:context, presence: true, reference: [path: "context"])
    field(:date, presence: true, reference: [path: "date"])
    field(:primary_source, strict_presence: true)
    field(:source, presence: true, reference: [path: "source"])
    field(:legal_entity, reference: [path: "legal_entity"])
    field(:manufacturer)
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
          {:date, Maybe.map(v, &create_datetime/1)}

        {"source", %{"type" => type, "value" => value}} ->
          {:source, Source.create(type, value)}

        {"report_origin", v} ->
          {:source, Source.create("report_origin", v)}

        {"performer", v} ->
          {:source, Source.create("performer", v)}

        {"legal_entity", v} ->
          {:legal_entity, Maybe.map(v, &Reference.create/1)}

        {"expiration_date", v} ->
          {:expiration_date, Maybe.map(v, &create_datetime/1)}

        {"vaccine_code", v} ->
          {:vaccine_code, CodeableConcept.create(v)}

        {"site", v} ->
          {:site, Maybe.map(v, &CodeableConcept.create/1)}

        {"route", v} ->
          {:route, Maybe.map(v, &CodeableConcept.create/1)}

        {"explanation", %{"type" => type, "value" => value}} ->
          {:explanation, Explanation.create(%{type => value})}

        {"explanation", v} ->
          {:explanation, Maybe.map(v, &Explanation.create/1)}

        {"dose_quantity", v} ->
          {:dose_quantity, Maybe.map(v, &Quantity.create/1)}

        {"reactions", nil} ->
          {:reactions, nil}

        {"reactions", v} ->
          {:reactions, Enum.map(v, &Reaction.create/1)}

        {"vaccination_protocols", nil} ->
          {:vaccination_protocols, nil}

        {"vaccination_protocols", v} ->
          {:vaccination_protocols, Enum.map(v, &VaccinationProtocol.create/1)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
