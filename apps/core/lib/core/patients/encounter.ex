defmodule Core.Encounter do
  @moduledoc false

  use Core.Schema
  alias Core.Coding
  alias Core.Diagnosis
  alias Core.Period
  alias Core.Reference

  embedded_schema do
    field(:id, presence: true)
    field(:status, presence: true)
    field(:status_history)
    field(:period, presence: true, reference: [path: "period"])
    field(:class, presence: true)
    field(:type, presence: true)
    field(:incoming_referrals)
    field(:duration)
    field(:reasons, presence: true)
    field(:diagnoses, presence: true)
    field(:service_provider)
    field(:division, presence: true)
    field(:actions, presence: true)
    field(:signed_content_links)
    field(:contexts, presence: true)

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"division", v} -> {:division, Reference.create(v)}
        {"diagnoses", v} -> {:diagnoses, Enum.map(v, &Diagnosis.create/1)}
        {"actions", v} -> {:actions, Enum.map(v, &Coding.create/1)}
        {"reasons", v} -> {:reasons, Enum.map(v, &Coding.create/1)}
        {"contexts", v} -> {:contexts, Enum.map(v, &Reference.create/1)}
        {"class", v} -> {:class, Coding.create(v)}
        {"type", v} -> {:type, Coding.create(v)}
        {"period", v} -> {:period, Period.create(v)}
        {k, v} -> {String.to_atom(k), v}
      end)
    )
  end
end
