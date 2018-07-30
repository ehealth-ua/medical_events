defmodule Core.Encounter do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.Coding
  alias Core.Diagnosis
  alias Core.Period
  alias Core.Reference
  alias Core.StatusHistory

  embedded_schema do
    field(:status)
    embeds_many(:status_history, StatusHistory)
    embeds_one(:period, Period)
    embeds_one(:class, Coding)
    embeds_many(:types, CodeableConcept)
    embeds_one(:episode, Reference)
    embeds_many(:incoming_referrals, Reference)
    embeds_many(:reasons, CodeableConcept)
    embeds_many(:diagnoses, Diagnosis)
    embeds_one(:service_provider, Reference)

    timestamps()
  end
end
