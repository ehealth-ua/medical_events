defmodule Core.Reference do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept

  embedded_schema do
    embeds_one :identifier, Identifier do
      embeds_one(:type, CodeableConcept)
      field(:system, :string)
      field(:value, :string)
    end
  end
end
