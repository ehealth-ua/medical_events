defmodule Core.Observation do
  @moduledoc false

  # use Ecto.Schema

  # alias Core.CodeableConcept
  # alias Core.Observations.Value
  # alias Core.Period
  # alias Core.Reference

  # schema "observations" do
  #   embeds_many(:based_on, Reference)
  #   embeds_many(:categories, CodeableConcept)
  #   embeds_one(:code, CodeableConcept)
  #   embeds_one(:patient, Reference)
  #   embeds_one(:encounter, Reference)
  #   field(:effective_date_time, :naive_datetime)
  #   embeds_one(:effective_period, Period)
  #   field(:issued, :naive_datetime)
  #   embeds_many(:performers, Reference)
  #   embeds_one(:value_codeable_concept, CodeableConcept)
  #   field(:value, Value)
  #   embeds_one(:data_absent_reason, CodeableConcept)
  #   embeds_one(:interpretation, CodeableConcept)
  #   field(:comment)
  #   embeds_one(:body_side, CodeableConcept)
  #   embeds_one(:method, CodeableConcept)

  #   timestamps()
  # end
end
