defmodule Core.ReferralRequest do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.Reference

  embedded_schema do
    embeds_many(:based_on, Reference)
    embeds_many(:replaces, Reference)
    field(:status)
    embeds_one(:type, CodeableConcept)
    embeds_one(:context, Reference)
    field(:authored_on, :naive_datetime)
    embeds_one(:recipient, Reference)
    embeds_one(:reason_code, CodeableConcept)

    timestamps()
  end
end
